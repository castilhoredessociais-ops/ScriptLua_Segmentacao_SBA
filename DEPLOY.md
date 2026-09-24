# Deploy — Segmentação SBA

Reorganização de 2026-09-07: motor TTS dedicado, isolado do self-service/Sonangol.

## Componentes

| Componente | Ficheiro local | Destino no servidor (ucalfusion005) |
|---|---|---|
| Script FreeSWITCH | `lua/ivr_sba_segmentacao.lua` | `/usr/share/freeswitch/scripts/ivr_sba_segmentacao.lua` |
| Serviço TTS Flask | `flask/tts_sba.py` | `/opt/gcloud-tts-api/tts_sba.py` |
| Unidade systemd | `deploy/tts-sba.service` | `/etc/systemd/system/tts-sba.service` |

- **Porta TTS dedicada:** 5006 (antes partilhava a 5004 com `ivr_selfservice.lua`/`ivr_saldo.lua` via `gcloud-tts-banking.service`)
- **Credencial GCP:** `/opt/APIs_keys/sba-segment-ucallkey.json` (projecto `sba-segment`, service account `sba-segmentacao@sba-segment.iam.gserviceaccount.com`)
- **API de dados do cliente:** `http://10.11.1.132:2323/api/ivr/info?number=` (porta corrigida, era 2123 nesta nota)
- **Logs/histórico:** `/var/log/freeswitch/segment_sba/history/YYYY-MM-DD.log`

## Porquê a mudança

O `gcloud-tts.service` original (porta 5002, `server.py`) morreu em algum momento e o `ivr_sba.lua` (então em produção) nunca foi actualizado — ficou a apontar para uma porta morta. Entretanto o self-service e o Sonangol foram sendo apontados para o `server_banking.py` (porta 5004), que na realidade tinha sido afinado (SSML, voz `pt-PT-Wavenet-B`) especificamente para o SBA. Esta reorganização devolve esse motor ao SBA (renomeado `tts_sba.py`, porta própria 5006) e deixa o self-service livre para, numa fase seguinte, ganhar o seu próprio motor dedicado.

## Estado do dialplan

**Em produção desde 2026-09-07**, testado de ponta a ponta com chamada real. DID confirmado: `923120101`.

## Caller-ID, ringback e pausa (adicionado 2026-09-2x)

- O script envia `sip_h_P-Asserted-Identity` e `sip_h_Remote-Party-ID` com o nome do cliente, para o 3CX mostrar o nome (não só o número) no ecrã do gestor. Depende do mapeamento `ParameterIn`/`ParameterOut` correcto no modelo do tronco 3CX (ver [[ucall-sba-segmentacao-status]] na memória do Eco para o fix do lado do 3CX).
- `session:sleep(1000)` logo após a mensagem de boas-vindas, antes de seguir para o encaminhamento — pausa de 1s para não soar corrido.
- `session:setVariable("ringback", "/var/lib/freeswitch/recordings/10.11.1.135/SBA/Hold_SBA.wav")` antes do `bridge` para o gestor — o cliente ouve este áudio (spot SBA) enquanto a chamada toca na extensão do gestor, em vez de silêncio. Ficheiro tem de pertencer a `www-data:www-data` para o script (que corre como esse utilizador) o conseguir ler.

## Menu "gestor não atende" (Call Flow App, separado deste script)

Quando o gestor não atende, quem trata a chamada a partir daí **deixa de ser este script Lua** — passa para uma Call Flow App do 3CX (`Gestor_Indisponivel`, projecto CFD separado) que toca um aviso, oferece "prima 1" (linha geral) ou "prima 2" (encerrar), com repetição automática (3 tentativas) e mensagem de despedida. Ver pasta do projecto CFD para o `.cfdproj`/`Main.flow`/áudios/pacote de build.

## Ficheiros arquivados (não apagados)

- `legacy/ivr_sba_ROT.lua` — versão anterior com marcadores de merge por resolver (`<<<<<<<`/`=======`/`>>>>>>>`), nunca funcional como está.
- No servidor, `ivr_sba.lua` (aponta para porta 5002 morta), `ivr_sba_sem_gtts.lua`, `ivr_comnovoflaskLog_SBA.lua` e `ivr_comnovoflask_sba.lua` ficam como estão até serem movidos para uma pasta `legacy/` no próprio servidor (passo manual, ver abaixo) — não apagar sem confirmar que nada mais os referencia.

## Passos de deploy (via WinSCP)

1. Copiar `lua/ivr_sba_segmentacao.lua` → `/usr/share/freeswitch/scripts/`
2. Copiar `flask/tts_sba.py` → `/opt/gcloud-tts-api/`
3. Copiar `deploy/tts-sba.service` → `/etc/systemd/system/`
4. No servidor:
   ```bash
   systemctl daemon-reload
   systemctl enable --now tts-sba.service
   systemctl status tts-sba.service
   curl -s -X POST http://127.0.0.1:5006/tts -H "Content-Type: application/json" \
        -d '{"texto":"Teste do motor de segmentação SBA."}' -o /tmp/teste_sba.wav
   file /tmp/teste_sba.wav
   ```
5. Confirmar áudio válido, só depois testar o `ivr_sba_segmentacao.lua` via chamada real (quando houver DDI/rota).
