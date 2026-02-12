#!/usr/bin/env python3
"""
🎤 Notitia Edge - Speech to Text Engine
Moteur de transcription basé sur Faster-Whisper (CTranslate2)
Optimisé pour la précision et les environnements Edge/IoT
"""

import os
import sys
import json
import wave
import tempfile
import threading
import queue
from pathlib import Path
from datetime import datetime
from typing import Optional, Callable

import numpy as np

# Audio processing
try:
    import sounddevice as sd
    import soundfile as sf
    from scipy import signal
    from scipy.io import wavfile
except ImportError:
    print("Installation des dépendances audio...")
    os.system("pip install sounddevice soundfile scipy")
    import sounddevice as sd
    import soundfile as sf
    from scipy import signal
    from scipy.io import wavfile

# Faster-Whisper
try:
    from faster_whisper import WhisperModel
except ImportError:
    print("Installation de Faster-Whisper...")
    os.system("pip install faster-whisper")
    from faster_whisper import WhisperModel


class AudioAmplifier:
    """
    🔊 Amplificateur audio intelligent
    Améliore les sons faibles tout en évitant la saturation
    """
    
    def __init__(self, target_db: float = -20.0, noise_gate_db: float = -50.0):
        self.target_db = target_db
        self.noise_gate_db = noise_gate_db
    
    def normalize(self, audio: np.ndarray) -> np.ndarray:
        """Normalise l'audio au niveau cible"""
        if len(audio) == 0:
            return audio
        
        # Calcul du niveau RMS actuel
        rms = np.sqrt(np.mean(audio ** 2))
        if rms < 1e-10:
            return audio
        
        current_db = 20 * np.log10(rms)
        
        # Si le son est trop faible, on amplifie
        if current_db < self.target_db:
            gain_db = self.target_db - current_db
            gain = 10 ** (gain_db / 20)
            audio = audio * gain
        
        # Limitation douce pour éviter la saturation
        audio = np.tanh(audio * 0.9) / 0.9
        
        return audio
    
    def apply_noise_gate(self, audio: np.ndarray, sample_rate: int) -> np.ndarray:
        """Applique un noise gate pour réduire le bruit de fond"""
        # Calcul de l'enveloppe
        frame_length = int(0.025 * sample_rate)  # 25ms frames
        hop_length = int(0.010 * sample_rate)    # 10ms hop
        
        envelope = np.array([
            np.sqrt(np.mean(audio[i:i+frame_length] ** 2))
            for i in range(0, len(audio) - frame_length, hop_length)
        ])
        
        # Seuil du noise gate
        threshold = 10 ** (self.noise_gate_db / 20)
        
        # Application du gate avec transition douce
        gate = np.where(envelope > threshold, 1.0, envelope / threshold)
        
        # Interpolation pour correspondre à la longueur de l'audio
        gate_interp = np.interp(
            np.arange(len(audio)),
            np.linspace(0, len(audio), len(gate)),
            gate
        )
        
        return audio * gate_interp
    
    def enhance_audio(self, audio: np.ndarray, sample_rate: int) -> np.ndarray:
        """Pipeline complet d'amélioration audio"""
        # 1. Noise gate
        audio = self.apply_noise_gate(audio, sample_rate)
        
        # 2. Filtre passe-haut pour enlever les basses fréquences (rumble)
        nyquist = sample_rate / 2
        low_cutoff = 80 / nyquist
        b, a = signal.butter(4, low_cutoff, btype='high')
        audio = signal.filtfilt(b, a, audio)
        
        # 3. Normalisation/Amplification
        audio = self.normalize(audio)
        
        return audio.astype(np.float32)


class NotitiaSTT:
    """
    🎯 Moteur de transcription Notitia
    Basé sur Faster-Whisper pour une précision maximale
    """
    
    MODELS = {
        "tiny": "tiny",
        "base": "base", 
        "small": "small",
        "medium": "medium",
        "large": "large-v3"
    }
    
    def __init__(
        self,
        model_size: str = "base",
        device: str = "auto",
        compute_type: str = "auto",
        language: str = "fr"
    ):
        """
        Initialise le moteur STT
        
        Args:
            model_size: tiny, base, small, medium, large
            device: cpu, cuda, auto
            compute_type: int8, float16, float32, auto
            language: Code langue (fr, en, etc.)
        """
        self.model_size = model_size
        self.language = language
        self.sample_rate = 16000
        self.amplifier = AudioAmplifier()
        
        # Détection automatique du device
        if device == "auto":
            try:
                import torch
                device = "cuda" if torch.cuda.is_available() else "cpu"
            except ImportError:
                device = "cpu"
        
        # Compute type optimal
        if compute_type == "auto":
            compute_type = "int8" if device == "cpu" else "float16"
        
        print(f"🚀 Chargement du modèle Faster-Whisper ({model_size})...")
        print(f"   Device: {device}, Compute: {compute_type}")
        
        self.model = WhisperModel(
            self.MODELS.get(model_size, model_size),
            device=device,
            compute_type=compute_type
        )
        
        print("✅ Modèle chargé avec succès!")
    
    def transcribe_file(
        self,
        audio_path: str,
        enhance_audio: bool = True,
        word_timestamps: bool = True
    ) -> dict:
        """
        Transcrit un fichier audio
        
        Args:
            audio_path: Chemin vers le fichier audio
            enhance_audio: Appliquer l'amélioration audio
            word_timestamps: Inclure les timestamps par mot
            
        Returns:
            Dictionnaire avec la transcription et les métadonnées
        """
        # Chargement de l'audio
        audio, sr = sf.read(audio_path)
        
        # Conversion mono si nécessaire
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)
        
        # Rééchantillonnage à 16kHz si nécessaire
        if sr != self.sample_rate:
            num_samples = int(len(audio) * self.sample_rate / sr)
            audio = signal.resample(audio, num_samples)
        
        # Amélioration audio
        if enhance_audio:
            audio = self.amplifier.enhance_audio(audio, self.sample_rate)
        
        return self._transcribe_audio(audio, word_timestamps)
    
    def transcribe_array(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000,
        enhance_audio: bool = True,
        word_timestamps: bool = True
    ) -> dict:
        """
        Transcrit un array numpy
        """
        # Rééchantillonnage si nécessaire
        if sample_rate != self.sample_rate:
            num_samples = int(len(audio) * self.sample_rate / sample_rate)
            audio = signal.resample(audio, num_samples)
        
        # Amélioration audio
        if enhance_audio:
            audio = self.amplifier.enhance_audio(audio, self.sample_rate)
        
        return self._transcribe_audio(audio, word_timestamps)
    
    def _transcribe_audio(self, audio: np.ndarray, word_timestamps: bool) -> dict:
        """Transcription interne"""
        segments, info = self.model.transcribe(
            audio,
            language=self.language,
            word_timestamps=word_timestamps,
            vad_filter=True,
            vad_parameters=dict(
                min_silence_duration_ms=500,
                speech_pad_ms=400
            )
        )
        
        result = {
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
            "segments": [],
            "full_text": "",
            "words": []
        }
        
        full_text_parts = []
        
        for segment in segments:
            seg_data = {
                "start": segment.start,
                "end": segment.end,
                "text": segment.text.strip(),
                "confidence": segment.avg_logprob
            }
            
            if word_timestamps and segment.words:
                seg_data["words"] = [
                    {
                        "word": word.word.strip(),
                        "start": word.start,
                        "end": word.end,
                        "probability": word.probability
                    }
                    for word in segment.words
                ]
                result["words"].extend(seg_data["words"])
            
            result["segments"].append(seg_data)
            full_text_parts.append(segment.text.strip())
        
        result["full_text"] = " ".join(full_text_parts)
        
        return result


class RealtimeSTT:
    """
    🎙️ Transcription en temps réel
    Pour utilisation avec microphone
    """
    
    def __init__(
        self,
        stt_engine: NotitiaSTT,
        chunk_duration: float = 3.0,
        overlap: float = 0.5
    ):
        self.stt = stt_engine
        self.chunk_duration = chunk_duration
        self.overlap = overlap
        self.sample_rate = 16000
        self.is_recording = False
        self.audio_queue = queue.Queue()
        self.results_queue = queue.Queue()
        
    def _audio_callback(self, indata, frames, time_info, status):
        """Callback pour la capture audio"""
        if status:
            print(f"⚠️ Status: {status}")
        self.audio_queue.put(indata.copy())
    
    def _process_audio(self):
        """Thread de traitement audio"""
        buffer = np.array([], dtype=np.float32)
        chunk_samples = int(self.chunk_duration * self.sample_rate)
        overlap_samples = int(self.overlap * self.sample_rate)
        
        while self.is_recording or not self.audio_queue.empty():
            try:
                audio_chunk = self.audio_queue.get(timeout=0.5)
                buffer = np.concatenate([buffer, audio_chunk.flatten()])
                
                # Traitement quand on a assez de données
                while len(buffer) >= chunk_samples:
                    chunk = buffer[:chunk_samples]
                    buffer = buffer[chunk_samples - overlap_samples:]
                    
                    # Transcription
                    result = self.stt.transcribe_array(
                        chunk,
                        self.sample_rate,
                        enhance_audio=True,
                        word_timestamps=True
                    )
                    
                    if result["full_text"].strip():
                        self.results_queue.put(result)
                        
            except queue.Empty:
                continue
    
    def start(self, callback: Optional[Callable] = None):
        """Démarre l'enregistrement en temps réel"""
        self.is_recording = True
        
        # Thread de traitement
        self.process_thread = threading.Thread(target=self._process_audio)
        self.process_thread.start()
        
        # Stream audio
        self.stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype=np.float32,
            callback=self._audio_callback,
            blocksize=int(self.sample_rate * 0.1)  # 100ms blocks
        )
        self.stream.start()
        
        print("🎙️ Enregistrement démarré... (Ctrl+C pour arrêter)")
        
        # Boucle de callback des résultats
        if callback:
            while self.is_recording:
                try:
                    result = self.results_queue.get(timeout=0.5)
                    callback(result)
                except queue.Empty:
                    continue
    
    def stop(self) -> list:
        """Arrête l'enregistrement et retourne tous les résultats"""
        self.is_recording = False
        self.stream.stop()
        self.stream.close()
        self.process_thread.join()
        
        results = []
        while not self.results_queue.empty():
            results.append(self.results_queue.get())
        
        return results


class NotitiaAPI:
    """
    🔌 API pour intégration Flutter/Mobile
    Expose les fonctionnalités via JSON
    """
    
    def __init__(self, stt_engine: NotitiaSTT):
        self.stt = stt_engine
    
    def transcribe(self, audio_path: str) -> str:
        """Retourne la transcription en JSON"""
        result = self.stt.transcribe_file(audio_path)
        return json.dumps(result, ensure_ascii=False, indent=2)
    
    def transcribe_base64(self, audio_base64: str, format: str = "wav") -> str:
        """Transcrit depuis audio encodé en base64"""
        import base64
        
        audio_bytes = base64.b64decode(audio_base64)
        
        with tempfile.NamedTemporaryFile(suffix=f".{format}", delete=False) as f:
            f.write(audio_bytes)
            temp_path = f.name
        
        try:
            result = self.stt.transcribe_file(temp_path)
            return json.dumps(result, ensure_ascii=False, indent=2)
        finally:
            os.unlink(temp_path)
    
    def get_words(self, audio_path: str) -> str:
        """Retourne uniquement les mots avec timestamps"""
        result = self.stt.transcribe_file(audio_path, word_timestamps=True)
        return json.dumps(result["words"], ensure_ascii=False, indent=2)


def save_transcription(result: dict, output_path: str, format: str = "json"):
    """Sauvegarde la transcription dans différents formats"""
    if format == "json":
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
    
    elif format == "txt":
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(result["full_text"])
    
    elif format == "srt":
        with open(output_path, "w", encoding="utf-8") as f:
            for i, seg in enumerate(result["segments"], 1):
                start = format_timestamp(seg["start"])
                end = format_timestamp(seg["end"])
                f.write(f"{i}\n{start} --> {end}\n{seg['text']}\n\n")


def format_timestamp(seconds: float) -> str:
    """Formate les secondes en timestamp SRT"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int((seconds % 1) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


# ============================================================================
# INTERFACE EN LIGNE DE COMMANDE
# ============================================================================

def main():
    """Point d'entrée CLI"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="🎤 Notitia STT - Transcription Speech-to-Text"
    )
    parser.add_argument("--file", "-f", help="Fichier audio à transcrire")
    parser.add_argument("--realtime", "-r", action="store_true", 
                        help="Mode temps réel (microphone)")
    parser.add_argument("--model", "-m", default="base",
                        choices=["tiny", "base", "small", "medium", "large"],
                        help="Taille du modèle")
    parser.add_argument("--language", "-l", default="fr",
                        help="Langue (fr, en, etc.)")
    parser.add_argument("--output", "-o", help="Fichier de sortie")
    parser.add_argument("--format", default="json",
                        choices=["json", "txt", "srt"],
                        help="Format de sortie")
    parser.add_argument("--gui", "-g", action="store_true",
                        help="Lancer l'interface graphique")
    
    args = parser.parse_args()
    
    if args.gui:
        from notitia_gui import NotitiaGUI
        app = NotitiaGUI()
        app.run()
        return
    
    # Initialisation du moteur
    stt = NotitiaSTT(model_size=args.model, language=args.language)
    
    if args.realtime:
        # Mode temps réel
        realtime = RealtimeSTT(stt)
        
        def on_result(result):
            print(f"\n📝 {result['full_text']}")
        
        try:
            realtime.start(callback=on_result)
        except KeyboardInterrupt:
            results = realtime.stop()
            print("\n\n🛑 Enregistrement terminé!")
            
            if args.output:
                combined = {
                    "segments": [],
                    "words": [],
                    "full_text": " ".join(r["full_text"] for r in results)
                }
                for r in results:
                    combined["segments"].extend(r["segments"])
                    combined["words"].extend(r["words"])
                
                save_transcription(combined, args.output, args.format)
                print(f"💾 Sauvegardé: {args.output}")
    
    elif args.file:
        # Mode fichier
        print(f"\n🎵 Transcription de: {args.file}")
        result = stt.transcribe_file(args.file)
        
        print(f"\n📝 Texte transcrit:\n{result['full_text']}")
        print(f"\n📊 Durée: {result['duration']:.2f}s")
        print(f"🌍 Langue détectée: {result['language']} ({result['language_probability']:.1%})")
        
        if args.output:
            save_transcription(result, args.output, args.format)
            print(f"\n💾 Sauvegardé: {args.output}")
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
