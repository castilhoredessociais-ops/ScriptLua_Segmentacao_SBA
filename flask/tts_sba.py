# tts_sba.py
# Serviço Flask de TTS dedicado à Segmentação SBA (Standard Bank Angola).
# Motor: Google Cloud Text-to-Speech, voz pt-PT-Wavenet-B, SSML com ênfase
# automática no nome do gestor ("gestor/gestora Fulano de Tal").
#
# Credencial: GOOGLE_APPLICATION_CREDENTIALS=/opt/APIs_keys/sba-segment-ucallkey.json
# Porta: 5006 (dedicada, não partilhada com outros produtos)
# Unidade systemd: tts-sba.service

from flask import Flask, request, send_file, jsonify
from google.cloud import texttospeech
import tempfile
import re
import os

app = Flask(__name__)

client = texttospeech.TextToSpeechClient()

GESTOR_PATTERN = re.compile(
    r"(gestor|gestora)\s+([A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+(?:\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ][a-záéíóúâêôãõç]+){1,3})",
    re.UNICODE
)

def build_banking_ssml(texto: str) -> str:
    texto = re.sub(r"\s+", " ", texto.strip())

    match = GESTOR_PATTERN.search(texto)
    if match:
        nome = match.group(2)
        texto = texto.replace(
            nome,
            f'<break time="200ms"/><emphasis level="strong">{nome}</emphasis>'
        )

    return f"""
    <speak>
        <prosody rate="102%" pitch="-2st">
            {texto}
        </prosody>
    </speak>
    """

def synthesize(texto: str) -> str:
    ssml_text = build_banking_ssml(texto)

    voice = texttospeech.VoiceSelectionParams(
        language_code="pt-PT",
        name="pt-PT-Wavenet-B"
    )

    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.LINEAR16,
        speaking_rate=1.02,
        pitch=-2.0
    )

    synthesis_input = texttospeech.SynthesisInput(ssml=ssml_text)

    response = client.synthesize_speech(
        input=synthesis_input,
        voice=voice,
        audio_config=audio_config
    )

    tmp = tempfile.NamedTemporaryFile(
        suffix=".wav",
        delete=False
    )

    tmp.write(response.audio_content)
    tmp.close()

    return tmp.name


@app.route("/tts", methods=["POST"])
def tts():
    try:
        data = request.get_json(force=True)
        texto = data.get("texto")

        if not texto:
            return jsonify({"error": "Texto ausente"}), 400

        wav = synthesize(texto)

        response = send_file(wav, mimetype="audio/wav")

        @response.call_on_close
        def cleanup():
            try:
                os.remove(wav)
            except:
                pass

        return response

    except Exception as e:
        print(f"[ERRO TTS] {e}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5006)
