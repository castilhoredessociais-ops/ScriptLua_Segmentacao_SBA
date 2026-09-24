--========================================================--
--  IVR SBA - Segmentação Inteligente de Clientes
--  Standard Bank Angola - COM HISTÓRICO E ESTATÍSTICAS
--  Motor TTS dedicado: tts-sba.service (porta 5006)
--========================================================--

package.path  = package.path .. ";/usr/share/lua/5.2/?.lua;/usr/local/share/lua/5.2/?.lua"
package.cpath = package.cpath .. ";/usr/lib/x86_64-linux-gnu/lua/5.2/?.so;/usr/local/lib/lua/5.2/?.so"

local json  = require("dkjson")
local http  = require("socket.http")
local ltn12 = require("ltn12")

http.TIMEOUT = 5

--================ CONFIG =================--

local TTS_URL      = "http://127.0.0.1:5006/tts"
local SBA_API_URL  = "http://10.11.1.132:2323/api/ivr/info?number="
local FS_DOMAIN    = "10.11.1.135"

local SUPORTE_BRIDGE_1 = "sofia/gateway/29cd5aec-392c-4b1a-9fbc-022f99e52822/923190888"
local SUPORTE_BRIDGE_2 = "sofia/gateway/8d89f777-3345-4b0a-8386-94bb7ce89368/923190888"
local GATEWAY_UUID     = "sofia/gateway/48e7015d-675a-4e32-8985-031fd26e7a41"

local BASE_DIR = "/var/log/freeswitch/segment_sba"
local HISTORY_DIR = BASE_DIR .. "/history"
os.execute("mkdir -p " .. HISTORY_DIR)

--================ FUNÇÃO LOG =================--

local function write_history(numero, cliente, segmento, gestor, estado, toque, conversa, motivo)
    local file = string.format("%s/%s.log", HISTORY_DIR, os.date("%Y-%m-%d"))

    local line = string.format("%s;%s;%s;%s;%s;%s;%ss;%ss;%s\n",
        os.date("%d/%m/%Y %H:%M"),
        numero or "-",
        cliente or "-",
        segmento or "-",
        gestor or "-",
        estado or "-",
        toque or "0",
        conversa or "0",
        motivo or "-"
    )

    local f = io.open(file, "a")
    if f then
        f:write(line)
        f:close()
    end
end

--================ PLAYBACK =================--

local function play_wav(file)
    if session:ready() then
        session:execute("playback", file)
    end
end

--================ TTS =================--

local function tts(texto)
    local uid = tostring(os.time())
    local raw = "/tmp/tts_sba_" .. uid .. "_raw.wav"
    local wav = "/tmp/tts_sba_" .. uid .. "_8k.wav"

    local body = json.encode({ texto = texto })
    local fh = io.open(raw, "wb")
    if not fh then return nil end

    local _, code = http.request{
        url = TTS_URL,
        method = "POST",
        headers = {
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = tostring(#body)
        },
        source = ltn12.source.string(body),
        sink   = ltn12.sink.file(fh)
    }

    if tonumber(code) ~= 200 then
        os.remove(raw)
        return nil
    end

    os.execute("ffmpeg -y -loglevel quiet -i " .. raw .. " -ar 8000 -ac 1 " .. wav)
    os.remove(raw)
    return wav
end

--================ INÍCIO =================--

if not session or not session:ready() then
    write_history("NOSESSION", "-", "-", "-", "Falhada", "0", "0", "NO_SESSION")
    return
end

session:answer()

local numero = session:getVariable("caller_id_number") or "-"

--================ API =================--

local resposta = {}

local body, api_code = http.request{
    url = SBA_API_URL .. numero,
    method = "POST",
    sink = ltn12.sink.table(resposta)
}

local raw_json = table.concat(resposta)
local data = json.decode(raw_json or "")

--================ FALLBACK =================--

if tonumber(api_code) ~= 200 or not data then
    session:execute("bridge", SUPORTE_BRIDGE_1)
    if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end

    local ringsec = session:getVariable("progresssec") or "0"
    local billsec = session:getVariable("billsec") or "0"

    write_history(numero, "-", "-", "-", "Falhada", ringsec, billsec, "API_ERROR")
    return
end

if not data.operator_name or not data.operator_extension then
    session:execute("bridge", SUPORTE_BRIDGE_1)
    if session:ready() then session:execute("bridge", SUPORTE_BRIDGE_2) end

    local ringsec = session:getVariable("progresssec") or "0"
    local billsec = session:getVariable("billsec") or "0"

    write_history(numero, "-", "-", "-", "Atendida (Geral)", ringsec, billsec, "NOT_FOUND")
    return
end

--================ TTS =================--

local texto = data.message or
    ("Bem-vindo. A sua chamada está a ser encaminhada para o seu operador, " ..
     data.operator_name .. ". Por favor, aguarde.")

local wav = tts(texto)
if wav then
    play_wav(wav)
    os.remove(wav)
    session:sleep(1000)
end

--================ DESTINO =================--

local nome_cliente = data.client_name or "Cliente"

-- Ajusta Caller ID e envia headers compatíveis com 3CX
session:setVariable("caller_id_name", nome_cliente)
session:setVariable("effective_caller_id_name", nome_cliente)
session:setVariable("effective_caller_id_number", numero)
session:setVariable("sip_h_P-Asserted-Identity", "\"" .. nome_cliente .. "\" <sip:" .. numero .. "@" .. FS_DOMAIN .. ">")
session:setVariable("sip_h_Remote-Party-ID", "\"" .. nome_cliente .. "\" <sip:" .. numero .. "@" .. FS_DOMAIN .. ">;party=calling;id-type=subscriber;screen=yes")

local destino
if #tostring(data.operator_extension) >= 5 then
    destino = GATEWAY_UUID .. "/" .. data.operator_extension
else
    destino = "user/" .. data.operator_extension .. "@" .. FS_DOMAIN
end

session:setVariable("ringback", "/var/lib/freeswitch/recordings/10.11.1.135/SBA/Hold_SBA.wav")
session:execute("bridge", destino)

--================ RESULTADO =================--

local ringsec = session:getVariable("progresssec") or "0"
local billsec = session:getVariable("billsec") or "0"
local hangup = session:getVariable("hangup_cause") or "UNKNOWN"

local estado
local motivo = "-"

if hangup == "NORMAL_CLEARING" and tonumber(billsec) > 0 then
    estado = "Atendida (Gestor)"
elseif hangup == "NO_ANSWER" then
    estado = "Não Atendida"
    motivo = "NO_ANSWER_MANAGER"
else
    estado = "Falhada"
    motivo = hangup
end

write_history(
    numero,
    data.client_name,
    data.segment,
    data.operator_name,
    estado,
    ringsec,
    billsec,
    motivo
)
