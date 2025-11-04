--========================================================--
--  IVR SBA - Standard Bank Angola
--  Autor: José Tomás & GPT
--  Data: 2025-11-03
--  Função: Roteamento inteligente de chamadas SBA com TTS funcional
--========================================================--

--== Corrige paths LuaSocket e dkjson ==--
package.path  = package.path .. ";/usr/share/lua/5.2/?.lua;/usr/local/share/lua/5.2/?.lua"
package.cpath = package.cpath .. ";/usr/lib/x86_64-linux-gnu/lua/5.2/?.so;/usr/local/lib/lua/5.2/?.so"

--== Dependências ==--
local json  = require("dkjson")
local http  = require("socket.http")
local ltn12 = require("ltn12")

--== Configurações ==--
local TTS_API_URL   = "http://127.0.0.1:5002/tts"
local SBA_API_URL   = "http://10.11.1.132:2123/api/ivr/info?number="
local AUDIO_DIR     = "/opt/gcloud-tts-api/audio/"
local SUPORTE_BRIDGE_1 = "sofia/gateway/29cd5aec-392c-4b1a-9fbc-022f99e52822/923190888"
local SUPORTE_BRIDGE_2 = "sofia/gateway/8d89f777-3345-4b0a-8386-94bb7ce89368/923190888"
local FS_DOMAIN = "10.11.1.135"
local LOG_DIR = "/var/log/freeswitch/sba-logs"

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

--== Função TTS via API Flask local (gera arquivo WAV diretamente) ==--
local function tts(texto)
    local output = "/tmp/tts_sba_" .. os.time() .. "_" .. math.random(1000,9999) .. ".wav"
    local body = json.encode({texto = texto, lang = "pt-PT"})
    local f = io.open(output, "wb")
    if not f then return nil end
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
    return (code == 200) and output or nil
end

--========================================================--
--  INÍCIO DO PROCESSAMENTO
--========================================================--

if not session or not session:ready() then return end

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

--== Decodifica resposta ==--
local data, _, err = json.decode(body)
if not data then
    log(session, "Falha ao decodificar JSON: " .. tostring(err))
end

--== Cliente não encontrado: fallback para suporte externo ==--
if not data or not data.manager_name or not data.manager_extension then
    log(session, "Cliente não encontrado. Redirecionando para linha de apoio externa...")
    if session:ready() then
        session:execute("bridge", SUPORTE_BRIDGE_1)
        if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end
    end
    return
end

--== Cliente encontrado ==--
local nome = data.client_name or "Cliente"
local gestor = data.manager_name or "Gestor"
local extensao = data.manager_extension or ""
log(session, "Cliente reconhecido: " .. nome .. " → gestor " .. gestor .. " (extensão " .. extensao .. ")")

--== Reproduz mensagem recebida da API via TTS funcional ==--
if data.message and session:ready() then
    local caminho_audio = tts(data.message)
    if caminho_audio then
        log(session, "Reproduzindo áudio TTS: " .. caminho_audio)
        session:streamFile(caminho_audio)
    else
        log(session, "Falha ao gerar TTS para mensagem do gestor.")
    end
end

--== Encaminha para o gestor (extensão interna com domínio correto e Caller ID atualizado) ==--
if extensao ~= "" and session:ready() then
    session:setVariable("effective_caller_id_name", nome)
    session:setVariable("caller_id_name", nome)
    local destino_interno = "user/" .. extensao .. "@" .. FS_DOMAIN
    log(session, "Encaminhando chamada para gestor internamente via: " .. destino_interno .. " com Caller ID: " .. nome)
    session:execute("bridge", destino_interno)
else
    log(session, "Extensão do gestor não encontrada. Redirecionando para linha de apoio externa...")
    if session:ready() then
        session:execute("bridge", SUPORTE_BRIDGE_1)
        if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end
    end
end

log(session, "Fim do processamento da chamada SBA para " .. numero)
