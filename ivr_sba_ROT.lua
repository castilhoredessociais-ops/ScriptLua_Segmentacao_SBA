--========================================================--
--  IVR SBA - Standard Bank Angola
--  Autor: José Tomás & GPT
--  Data: 2025-11-04 (Corrigido para TTS completo, timing de áudio e roteamento por dígitos)
--  Função: Roteamento inteligente de chamadas SBA com TTS integral
--========================================================--

package.path  = package.path .. ";/usr/share/lua/5.2/?.lua;/usr/local/share/lua/5.2/?.lua"
package.cpath = package.cpath .. ";/usr/lib/x86_64-linux-gnu/lua/5.2/?.so;/usr/local/lib/lua/5.2/?.so"

local json  = require("dkjson")
local http  = require("socket.http")
local ltn12 = require("ltn12")

local TTS_API_URL   = "http://127.0.0.1:5002/tts"
local SBA_API_URL   = "http://10.11.1.132:2123/api/ivr/info?number="
local FS_DOMAIN     = "10.11.1.135"
local SUPORTE_BRIDGE_1 = "sofia/gateway/29cd5aec-392c-4b1a-9fbc-022f99e52822/923190888"
local SUPORTE_BRIDGE_2 = "sofia/gateway/8d89f777-3345-4b0a-8386-94bb7ce89368/923190888"
local GATEWAY_UUID  = "sofia/gateway/c5c0b204-6528-48e5-8b57-51f871c32334"
local LOG_DIR       = "/var/log/freeswitch/sba-logs"
local TMP_PATTERN   = "/tmp/tts_sba_*.wav"

os.execute("mkdir -p " .. LOG_DIR)

--== Funções de log ==--
local function init_log(session)
    local uuid = session:getVariable("uuid") or os.date("%H%M%S")
    return string.format("%s/sba-ivr-%s-%s.log", LOG_DIR, os.date("%Y-%m-%d"), uuid)
end

local function log(session, msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("%s [SBA-IVR] %s\n", timestamp, msg)
    freeswitch.consoleLog("INFO", line)
    local f = io.open(init_log(session), "a")
    if f then f:write(line) f:close() end
end

--== Função TTS: gera WAV 8kHz mono e garante arquivo completo ==--
local function tts(texto, session)
    local output_raw = "/tmp/tts_sba_" .. os.time() .. "_" .. math.random(1000,9999) .. "_raw.wav"
    local output_8k  = output_raw:gsub("_raw", "_8k")
    local body = json.encode({texto = texto, lang = "pt-PT"})

    local f = io.open(output_raw, "wb")
    if not f then 
        log(session, "Erro ao abrir arquivo raw para TTS")
        return nil 
    end

    local res, code = http.request{
        url = TTS_API_URL,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body)
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.file(f)
    }

    pcall(function() f:close() end)

    if code ~= 200 then 
        log(session, "Erro na API TTS: código " .. tostring(code))
        os.remove(output_raw)
        return nil 
    end

    local ffmpeg_cmd = "ffmpeg -y -i " .. output_raw .. " -ar 8000 -ac 1 -f wav " .. output_8k .. " 2>/dev/null"
    local success = os.execute(ffmpeg_cmd)
    os.remove(output_raw)

    if not success or not io.open(output_8k, "rb") then
        log(session, "Erro na conversão ffmpeg ou arquivo 8k não criado")
        return nil
    end

    local file_handle = io.open(output_8k, "rb")
    local file_size = file_handle:seek("end")
    file_handle:close()
    if file_size < 100 then
        log(session, "Arquivo TTS muito pequeno ou corrompido: " .. tostring(file_size) .. " bytes")
        os.remove(output_8k)
        return nil
    end

    log(session, "TTS gerado com sucesso: " .. output_8k .. " (tamanho: " .. tostring(file_size) .. " bytes)")
    return output_8k
end

--== Limpeza de arquivos temporários ==--
local function limpar_temp()
    for file in io.popen("ls " .. TMP_PATTERN .. " 2>/dev/null"):lines() do
        os.remove(file)
    end
end

--========================================================--
--  INÍCIO DO PROCESSAMENTO
--========================================================--

if not session or not session:ready() then return end

session:answer()
while not session:ready() do
    freeswitch.msleep(50)
end

local numero = session:getVariable("caller_id_number") or "desconhecido"
log(session, "Nova chamada recebida de " .. numero)

--== Consulta API SBA ==--
local resposta = {}
http.request{
    url = SBA_API_URL .. numero,
    method = "POST",
    sink = ltn12.sink.table(resposta)
}
local body = table.concat(resposta)
log(session, "Resposta da API SBA: " .. (body or "vazia"))

local data, _, err = json.decode(body)
if not data then
    log(session, "Falha ao decodificar JSON: " .. tostring(err))
end

--== Cliente não encontrado: fallback ==
if not data or not data.manager_name or not data.manager_extension then
    log(session, "Cliente não encontrado. Redirecionando para linha de apoio externa...")
    if session:ready() then
        session:execute("bridge", SUPORTE_BRIDGE_1)
        if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end
    end
    limpar_temp()
    return
end

--== Cliente encontrado ==
local nome = data.client_name or "Cliente"
local gestor = data.manager_name or "Gestor"
local extensao = data.manager_extension or ""
log(session, "Cliente reconhecido: " .. nome .. " → gestor " .. gestor .. " (extensão " .. extensao .. ")")

--== Reproduz mensagem do gestor via TTS ==
if data.message and session:ready() then
    local caminho_audio = tts(data.message, session)
    if caminho_audio then
        freeswitch.msleep(700)
        session:streamFile(caminho_audio)
        os.remove(caminho_audio)
    else
        log(session, "Falha ao gerar TTS para mensagem do gestor.")
    end
end

--== Encaminha para o gestor (condicional por número de dígitos) ==
if extensao ~= "" and session:ready() then
    session:setVariable("effective_caller_id_name", nome)
    session:setVariable("caller_id_name", nome)
    local destino
    if #tostring(extensao) >= 5 then
        destino = GATEWAY_UUID .. "/" .. extensao
        log(session, "Extensão com >=5 dígitos. Encaminhando via gateway: " .. destino)
    else
        destino = "user/" .. extensao .. "@" .. FS_DOMAIN
        log(session, "Extensão com <=4 dígitos. Encaminhando internamente: " .. destino)
    end
    session:execute("bridge", destino)
else
    log(session, "Extensão do gestor não encontrada. Redirecionando para linha de apoio externa...")
    if session:ready() then
        session:execute("bridge", SUPORTE_BRIDGE_1)
        if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end
    end
end

--== Limpeza final ==
limpar_temp()
log(session, "Fim do processamento da chamada SBA para " .. numero)
