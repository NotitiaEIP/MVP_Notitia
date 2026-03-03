#!/usr/bin/env python3
"""
🔌 Notitia API Server
Serveur HTTP/WebSocket pour intégration Flutter/Mobile
"""

import os
import sys
import json
import base64
import tempfile
import asyncio
from pathlib import Path
from typing import Optional
from datetime import datetime

# Web server
try:
    from flask import Flask, request, jsonify
    from flask_cors import CORS
except ImportError:
    os.system("pip install flask flask-cors")
    from flask import Flask, request, jsonify
    from flask_cors import CORS

try:
    import numpy as np
    import soundfile as sf
except ImportError:
    os.system("pip install numpy soundfile")
    import numpy as np
    import soundfile as sf

from notitia_stt import NotitiaSTT, AudioAmplifier, save_transcription
from fusion_system import NotitiaFusionSTT, WhisperMistralFusion
from mistral_integration import MistralCorrector, MistralConfig, CorrectionLevel


# ============================================================================
# FLASK API SERVER
# ============================================================================

app = Flask(__name__)
CORS(app)  # Permet les requêtes cross-origin pour Flutter

# Instance globale du moteur STT (avec fusion IA)
stt_engine: Optional[NotitiaSTT] = None
fusion_engine: Optional[NotitiaFusionSTT] = None
mistral_corrector: Optional[MistralCorrector] = None


def get_stt():
    """Récupère ou initialise le moteur STT basique"""
    global stt_engine
    if stt_engine is None:
        stt_engine = NotitiaSTT(model_size="base", language="fr")
    return stt_engine


def get_fusion_stt():
    """Récupère ou initialise le moteur STT avec fusion Whisper+Mistral"""
    global fusion_engine
    if fusion_engine is None:
        fusion_engine = NotitiaFusionSTT(
            whisper_model="base",
            language="fr",
            enable_noise_reduction=True,
            enable_fusion=True
        )
    return fusion_engine


def get_mistral_corrector():
    """Récupère ou initialise le correcteur Mistral"""
    global mistral_corrector
    if mistral_corrector is None:
        try:
            mistral_corrector = MistralCorrector()
        except ValueError:
            return None
    return mistral_corrector


@app.route("/health", methods=["GET"])
def health():
    """Endpoint de santé"""
    corrector = get_mistral_corrector()
    return jsonify({
        "status": "ok",
        "service": "Notitia STT API",
        "version": "2.1.0",
        "timestamp": datetime.now().isoformat(),
        "features": {
            "whisper": True,
            "mistral_fusion": corrector is not None,
            "noise_reduction": True
        }
    })


@app.route("/models", methods=["GET"])
def list_models():
    """Liste les modèles disponibles"""
    return jsonify({
        "models": [
            {"id": "tiny", "name": "Tiny", "size": "~75MB", "speed": "fastest"},
            {"id": "base", "name": "Base", "size": "~150MB", "speed": "fast"},
            {"id": "small", "name": "Small", "size": "~500MB", "speed": "medium"},
            {"id": "medium", "name": "Medium", "size": "~1.5GB", "speed": "slow"},
            {"id": "large", "name": "Large-v3", "size": "~3GB", "speed": "slowest"}
        ],
        "languages": ["fr", "en", "es", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko"]
    })


@app.route("/transcribe/file", methods=["POST"])
def transcribe_file():
    """
    Transcrit un fichier audio uploadé
    
    Body (multipart/form-data):
        - file: Fichier audio
        - language: Code langue (optionnel, défaut: fr)
        - enhance_audio: true/false (optionnel, défaut: true)
        - word_timestamps: true/false (optionnel, défaut: true)
    """
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400
    
    file = request.files["file"]
    language = request.form.get("language", "fr")
    enhance_audio = request.form.get("enhance_audio", "true").lower() == "true"
    word_timestamps = request.form.get("word_timestamps", "true").lower() == "true"
    
    # Sauvegarde temporaire
    suffix = Path(file.filename).suffix if file.filename else ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        file.save(tmp.name)
        temp_path = tmp.name
    
    try:
        stt = get_stt()
        result = stt.transcribe_file(
            temp_path,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        os.unlink(temp_path)


@app.route("/transcribe/base64", methods=["POST"])
def transcribe_base64():
    """
    Transcrit un audio encodé en base64
    
    Body (JSON):
    {
        "audio": "base64_encoded_audio",
        "format": "wav",  // optionnel
        "language": "fr",  // optionnel
        "enhance_audio": true,  // optionnel
        "word_timestamps": true  // optionnel
    }
    """
    data = request.get_json()
    
    if not data or "audio" not in data:
        return jsonify({"error": "Champ 'audio' manquant"}), 400
    
    audio_b64 = data["audio"]
    audio_format = data.get("format", "wav")
    language = data.get("language", "fr")
    enhance_audio = data.get("enhance_audio", True)
    word_timestamps = data.get("word_timestamps", True)
    
    try:
        # Décodage base64
        audio_bytes = base64.b64decode(audio_b64)
        
        # Sauvegarde temporaire
        with tempfile.NamedTemporaryFile(suffix=f".{audio_format}", delete=False) as tmp:
            tmp.write(audio_bytes)
            temp_path = tmp.name
        
        stt = get_stt()
        result = stt.transcribe_file(
            temp_path,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        
        os.unlink(temp_path)
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/transcribe/pcm", methods=["POST"])
def transcribe_pcm():
    """
    Transcrit des données PCM brutes (pour streaming Flutter)
    
    Body (JSON):
    {
        "samples": [0.1, -0.2, ...],  // Float32 samples
        "sample_rate": 16000,
        "language": "fr",
        "enhance_audio": true,
        "word_timestamps": true
    }
    """
    data = request.get_json()
    
    if not data or "samples" not in data:
        return jsonify({"error": "Champ 'samples' manquant"}), 400
    
    samples = np.array(data["samples"], dtype=np.float32)
    sample_rate = data.get("sample_rate", 16000)
    language = data.get("language", "fr")
    enhance_audio = data.get("enhance_audio", True)
    word_timestamps = data.get("word_timestamps", True)
    
    try:
        stt = get_stt()
        result = stt.transcribe_array(
            samples,
            sample_rate,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/config", methods=["POST"])
def set_config():
    """
    Configure le moteur STT
    
    Body (JSON):
    {
        "model": "base",
        "language": "fr"
    }
    """
    global stt_engine, fusion_engine
    
    data = request.get_json()
    model = data.get("model", "base")
    language = data.get("language", "fr")
    
    try:
        stt_engine = NotitiaSTT(model_size=model, language=language)
        fusion_engine = NotitiaFusionSTT(
            whisper_model=model,
            language=language,
            enable_noise_reduction=True,
            enable_fusion=True
        )
        return jsonify({
            "status": "ok",
            "model": model,
            "language": language
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================================
# ENDPOINTS AVEC FUSION IA (WHISPER + MISTRAL)
# ============================================================================

@app.route("/transcribe/fusion/file", methods=["POST"])
def transcribe_fusion_file():
    """
    Transcrit un fichier audio avec fusion Whisper+Mistral
    
    Body (multipart/form-data):
        - file: Fichier audio
        - context: Indice de contexte (optionnel, ex: "réunion médicale")
        - language: Code langue (optionnel, défaut: fr)
    """
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400
    
    file = request.files["file"]
    context = request.form.get("context", None)
    language = request.form.get("language", "fr")
    
    suffix = Path(file.filename).suffix if file.filename else ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        file.save(tmp.name)
        temp_path = tmp.name
    
    try:
        fusion_stt = get_fusion_stt()
        result = fusion_stt.transcribe_file(
            temp_path,
            context_hint=context,
            enhance_audio=True,
            word_timestamps=True
        )
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        os.unlink(temp_path)


@app.route("/transcribe/fusion/base64", methods=["POST"])
def transcribe_fusion_base64():
    """
    Transcrit un audio base64 avec fusion Whisper+Mistral
    
    Body (JSON):
    {
        "audio": "base64_encoded_audio",
        "format": "wav",
        "context": "réunion technique",  // optionnel
        "language": "fr"
    }
    """
    data = request.get_json()
    
    if not data or "audio" not in data:
        return jsonify({"error": "Champ 'audio' manquant"}), 400
    
    audio_b64 = data["audio"]
    audio_format = data.get("format", "wav")
    context = data.get("context", None)
    
    try:
        audio_bytes = base64.b64decode(audio_b64)
        
        with tempfile.NamedTemporaryFile(suffix=f".{audio_format}", delete=False) as tmp:
            tmp.write(audio_bytes)
            temp_path = tmp.name
        
        fusion_stt = get_fusion_stt()
        result = fusion_stt.transcribe_file(
            temp_path,
            context_hint=context,
            enhance_audio=True,
            word_timestamps=True
        )
        
        os.unlink(temp_path)
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/correct/text", methods=["POST"])
def correct_text():
    """
    Corrige un texte déjà transcrit avec Mistral
    
    Body (JSON):
    {
        "text": "texte à corriger",
        "context": "contexte optionnel",
        "level": "medium"  // light, medium, full
    }
    """
    data = request.get_json()
    
    if not data or "text" not in data:
        return jsonify({"error": "Champ 'text' manquant"}), 400
    
    text = data["text"]
    context = data.get("context", None)
    level_str = data.get("level", "medium")
    
    corrector = get_mistral_corrector()
    if corrector is None:
        return jsonify({
            "original": text,
            "corrected": text,
            "error": "Mistral non disponible - clé API manquante"
        })
    
    try:
        level = CorrectionLevel(level_str)
    except ValueError:
        level = CorrectionLevel.MEDIUM
    
    try:
        corrected = corrector.correct_text(text, context=context, level=level)
        return jsonify({
            "original": text,
            "corrected": corrected,
            "level": level_str,
            "mistral_applied": True
        })
    except Exception as e:
        return jsonify({
            "original": text,
            "corrected": text,
            "error": str(e)
        })


# ============================================================================
# MAIN
# ============================================================================

def main():
    """Lance le serveur API"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Notitia STT API Server")
    parser.add_argument("--host", default="0.0.0.0", help="Adresse d'écoute")
    parser.add_argument("--port", type=int, default=5000, help="Port d'écoute")
    parser.add_argument("--model", default="base", help="Modèle initial")
    parser.add_argument("--language", default="fr", help="Langue par défaut")
    parser.add_argument("--debug", action="store_true", help="Mode debug")
    
    args = parser.parse_args()
    
    # Pré-chargement du modèle avec fusion
    global stt_engine, fusion_engine
    print(f"🚀 Chargement du modèle {args.model} avec fusion Mistral...")
    stt_engine = NotitiaSTT(model_size=args.model, language=args.language)
    
    try:
        fusion_engine = NotitiaFusionSTT(
            whisper_model=args.model,
            language=args.language,
            enable_noise_reduction=True,
            enable_fusion=True
        )
        fusion_status = "✅ Activée"
    except Exception as e:
        print(f"⚠️ Fusion non disponible: {e}")
        fusion_status = "❌ Non disponible"
    
    print(f"""
╔══════════════════════════════════════════════════════════════╗
║           🎤 Notitia STT API Server v2.1                     ║
╠══════════════════════════════════════════════════════════════╣
║  Endpoints Whisper (Local):                                  ║
║    GET  /health             - État du serveur                ║
║    GET  /models             - Liste des modèles              ║
║    POST /transcribe/file    - Transcription fichier          ║
║    POST /transcribe/base64  - Transcription base64           ║
║    POST /transcribe/pcm     - Transcription PCM              ║
║    POST /config             - Configuration                  ║
╠══════════════════════════════════════════════════════════════╣
║  Endpoints Fusion IA (Whisper + Mistral):                    ║
║    POST /transcribe/fusion/file   - Fichier + IA             ║
║    POST /transcribe/fusion/base64 - Base64 + IA              ║
║    POST /correct/text             - Correction texte         ║
╠══════════════════════════════════════════════════════════════╣
║  Fusion Mistral: {fusion_status:40}║
║  Server: http://{args.host}:{args.port}                          ║
╚══════════════════════════════════════════════════════════════╝
    """)
    
    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == "__main__":
    main()
