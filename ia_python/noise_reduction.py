#!/usr/bin/env python3
"""
🔇 Notitia Edge - Module de Réduction de Bruit
Suppression avancée des bruits ambiants et parasites
Basé sur: noisereduce, RNNoise (Mozilla), Spectral Gating
"""

import os
import numpy as np
from typing import Optional, Tuple
from scipy import signal
from scipy.io import wavfile

# Installation automatique des dépendances
try:
    import noisereduce as nr
except ImportError:
    print("📦 Installation de noisereduce...")
    os.system("pip install noisereduce")
    import noisereduce as nr

try:
    import soundfile as sf
except ImportError:
    os.system("pip install soundfile")
    import soundfile as sf


class NoiseReducer:
    """
    🔇 Réducteur de bruit avancé
    
    Combine plusieurs techniques:
    1. Spectral Gating (noisereduce)
    2. Filtre passe-bande pour la voix humaine
    3. Noise Gate adaptatif
    4. Suppression des silences
    """
    
    # Plage de fréquences de la voix humaine
    VOICE_FREQ_LOW = 85      # Hz (voix grave masculine)
    VOICE_FREQ_HIGH = 3500   # Hz (voix aiguë, sibilantes)
    
    def __init__(
        self,
        strength: float = 0.75,
        voice_enhance: bool = True,
        remove_silence: bool = True,
        silence_threshold: float = 0.01
    ):
        """
        Initialise le réducteur de bruit
        
        Args:
            strength: Force de la réduction (0.0 à 1.0)
            voice_enhance: Améliorer les fréquences vocales
            remove_silence: Supprimer les silences
            silence_threshold: Seuil de détection du silence
        """
        self.strength = np.clip(strength, 0.0, 1.0)
        self.voice_enhance = voice_enhance
        self.remove_silence = remove_silence
        self.silence_threshold = silence_threshold
    
    def reduce_noise(
        self,
        audio: np.ndarray,
        sample_rate: int,
        noise_sample: Optional[np.ndarray] = None
    ) -> np.ndarray:
        """
        Réduit le bruit d'un signal audio
        
        Args:
            audio: Signal audio (numpy array)
            sample_rate: Fréquence d'échantillonnage
            noise_sample: Échantillon de bruit pur (optionnel, auto-détecté sinon)
            
        Returns:
            Audio débruité
        """
        # Conversion en float32 si nécessaire
        if audio.dtype != np.float32:
            if np.issubdtype(audio.dtype, np.integer):
                audio = audio.astype(np.float32) / np.iinfo(audio.dtype).max
            else:
                audio = audio.astype(np.float32)
        
        # Mono si stéréo
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)
        
        # 1. Spectral Gating (noisereduce)
        audio = self._spectral_gating(audio, sample_rate, noise_sample)
        
        # 2. Filtre passe-bande pour la voix
        if self.voice_enhance:
            audio = self._bandpass_filter(audio, sample_rate)
        
        # 3. Noise Gate adaptatif
        audio = self._adaptive_noise_gate(audio, sample_rate)
        
        # 4. Suppression des silences
        if self.remove_silence:
            audio = self._remove_silence(audio, sample_rate)
        
        # 5. Normalisation finale
        audio = self._normalize(audio)
        
        return audio
    
    def _spectral_gating(
        self,
        audio: np.ndarray,
        sample_rate: int,
        noise_sample: Optional[np.ndarray] = None
    ) -> np.ndarray:
        """Applique le spectral gating via noisereduce"""
        # Paramètres adaptés à la force demandée
        prop_decrease = 0.5 + (self.strength * 0.4)  # 0.5 à 0.9
        
        if noise_sample is not None:
            # Utilise l'échantillon de bruit fourni
            reduced = nr.reduce_noise(
                y=audio,
                sr=sample_rate,
                y_noise=noise_sample,
                prop_decrease=prop_decrease,
                stationary=False
            )
        else:
            # Auto-détection du profil de bruit
            reduced = nr.reduce_noise(
                y=audio,
                sr=sample_rate,
                prop_decrease=prop_decrease,
                stationary=False,
                n_fft=2048,
                hop_length=512
            )
        
        return reduced
    
    def _bandpass_filter(
        self,
        audio: np.ndarray,
        sample_rate: int
    ) -> np.ndarray:
        """Filtre passe-bande centré sur les fréquences vocales"""
        nyquist = sample_rate / 2
        
        # Fréquences normalisées
        low = self.VOICE_FREQ_LOW / nyquist
        high = min(self.VOICE_FREQ_HIGH / nyquist, 0.99)
        
        # Filtre Butterworth ordre 4
        b, a = signal.butter(4, [low, high], btype='band')
        
        # Application du filtre (forward-backward pour éviter le déphasage)
        filtered = signal.filtfilt(b, a, audio)
        
        # Mix avec l'original selon la force
        mix_ratio = 0.3 + (self.strength * 0.5)  # 30% à 80% de filtré
        return audio * (1 - mix_ratio) + filtered * mix_ratio
    
    def _adaptive_noise_gate(
        self,
        audio: np.ndarray,
        sample_rate: int
    ) -> np.ndarray:
        """Noise gate adaptatif basé sur l'enveloppe du signal"""
        # Calcul de l'enveloppe RMS
        frame_length = int(0.02 * sample_rate)  # 20ms
        hop_length = int(0.005 * sample_rate)   # 5ms
        
        # Calcul RMS par frame
        n_frames = 1 + (len(audio) - frame_length) // hop_length
        rms = np.zeros(n_frames)
        
        for i in range(n_frames):
            start = i * hop_length
            end = start + frame_length
            frame = audio[start:end]
            rms[i] = np.sqrt(np.mean(frame ** 2))
        
        # Seuil adaptatif (percentile bas du RMS)
        threshold = np.percentile(rms, 15) * (2 - self.strength)
        
        # Création du gate smoothé
        gate = np.where(rms > threshold, 1.0, rms / (threshold + 1e-10))
        gate = np.clip(gate, 0.0, 1.0)
        
        # Lissage du gate
        from scipy.ndimage import uniform_filter1d
        gate = uniform_filter1d(gate, size=5)
        
        # Interpolation pour correspondre à la longueur audio
        gate_interp = np.interp(
            np.arange(len(audio)),
            np.linspace(0, len(audio), len(gate)),
            gate
        )
        
        return audio * gate_interp
    
    def _remove_silence(
        self,
        audio: np.ndarray,
        sample_rate: int,
        min_speech_duration: float = 0.1,
        min_silence_duration: float = 0.3
    ) -> np.ndarray:
        """Supprime les longs silences tout en gardant les pauses naturelles"""
        frame_length = int(0.02 * sample_rate)
        hop_length = int(0.01 * sample_rate)
        
        # Détection des segments vocaux
        n_frames = 1 + (len(audio) - frame_length) // hop_length
        energy = np.zeros(n_frames)
        
        for i in range(n_frames):
            start = i * hop_length
            end = start + frame_length
            energy[i] = np.sqrt(np.mean(audio[start:end] ** 2))
        
        # Seuil de silence
        threshold = np.percentile(energy, 20) * 1.5
        is_speech = energy > threshold
        
        # Lissage pour éviter les coupures brusques
        from scipy.ndimage import binary_dilation, binary_erosion
        is_speech = binary_dilation(is_speech, iterations=3)
        is_speech = binary_erosion(is_speech, iterations=2)
        
        # Reconstruction du signal
        output_segments = []
        in_speech = False
        speech_start = 0
        
        for i, speech in enumerate(is_speech):
            if speech and not in_speech:
                in_speech = True
                speech_start = i * hop_length
            elif not speech and in_speech:
                in_speech = False
                speech_end = i * hop_length + frame_length
                if speech_end - speech_start > min_speech_duration * sample_rate:
                    output_segments.append(audio[speech_start:speech_end])
        
        # Dernier segment
        if in_speech:
            output_segments.append(audio[speech_start:])
        
        if output_segments:
            # Ajoute de courtes pauses entre les segments
            pause = np.zeros(int(0.1 * sample_rate))
            result = []
            for i, seg in enumerate(output_segments):
                result.append(seg)
                if i < len(output_segments) - 1:
                    result.append(pause)
            return np.concatenate(result)
        
        return audio
    
    def _normalize(self, audio: np.ndarray, target_db: float = -3.0) -> np.ndarray:
        """Normalise le volume au niveau cible"""
        rms = np.sqrt(np.mean(audio ** 2))
        if rms < 1e-10:
            return audio
        
        current_db = 20 * np.log10(rms)
        gain_db = target_db - current_db - 20  # -20 car RMS pas peak
        gain = 10 ** (gain_db / 20)
        
        # Limite le gain pour éviter l'amplification excessive
        gain = np.clip(gain, 0.1, 10.0)
        
        normalized = audio * gain
        
        # Soft clipping pour éviter la saturation
        return np.tanh(normalized * 0.95) / 0.95


class RNNoiseReducer:
    """
    🔇 Réducteur basé sur RNNoise (Mozilla)
    
    RNNoise est un réseau de neurones léger spécialement entraîné
    pour la suppression de bruit sur la voix en temps réel.
    
    https://github.com/xiph/rnnoise
    """
    
    def __init__(self):
        self._rnnoise = None
        self._available = self._check_rnnoise()
    
    def _check_rnnoise(self) -> bool:
        """Vérifie si RNNoise est disponible"""
        try:
            import rnnoise
            self._rnnoise = rnnoise
            return True
        except ImportError:
            try:
                print("📦 Installation de rnnoise-python...")
                os.system("pip install rnnoise-python")
                import rnnoise
                self._rnnoise = rnnoise
                return True
            except:
                print("⚠️ RNNoise non disponible, utilisation du fallback")
                return False
    
    @property
    def available(self) -> bool:
        return self._available
    
    def reduce_noise(
        self,
        audio: np.ndarray,
        sample_rate: int
    ) -> np.ndarray:
        """Applique RNNoise au signal"""
        if not self._available:
            return audio
        
        # RNNoise nécessite 48kHz
        if sample_rate != 48000:
            # Resample à 48kHz
            from scipy.signal import resample
            n_samples_48k = int(len(audio) * 48000 / sample_rate)
            audio_48k = resample(audio, n_samples_48k)
        else:
            audio_48k = audio
        
        # Conversion en int16 pour RNNoise
        audio_int16 = (audio_48k * 32767).astype(np.int16)
        
        # Application de RNNoise
        denoiser = self._rnnoise.RNNoise()
        denoised = denoiser.process_audio(audio_int16)
        
        # Reconversion en float32
        denoised_float = denoised.astype(np.float32) / 32767.0
        
        # Resample back si nécessaire
        if sample_rate != 48000:
            denoised_float = resample(denoised_float, len(audio))
        
        return denoised_float


class AdvancedNoiseReducer:
    """
    🎯 Réducteur de bruit avancé combinant plusieurs techniques
    
    Pipeline:
    1. RNNoise (si disponible) - Deep learning temps réel
    2. Spectral Gating - Suppression par masquage spectral
    3. Voice Enhancement - Amélioration des fréquences vocales
    4. Adaptive Gate - Suppression des bruits résiduels
    """
    
    def __init__(
        self,
        strength: float = 0.75,
        use_rnnoise: bool = True,
        use_spectral: bool = True,
        voice_enhance: bool = True
    ):
        self.strength = strength
        self.use_rnnoise = use_rnnoise
        self.use_spectral = use_spectral
        self.voice_enhance = voice_enhance
        
        # Initialisation des réducteurs
        self.spectral_reducer = NoiseReducer(
            strength=strength,
            voice_enhance=voice_enhance,
            remove_silence=False
        )
        
        self.rnnoise_reducer = RNNoiseReducer() if use_rnnoise else None
    
    def process(
        self,
        audio: np.ndarray,
        sample_rate: int,
        noise_profile: Optional[np.ndarray] = None
    ) -> Tuple[np.ndarray, dict]:
        """
        Traite l'audio avec le pipeline complet
        
        Returns:
            Tuple (audio débruité, statistiques)
        """
        stats = {
            "original_rms": float(np.sqrt(np.mean(audio ** 2))),
            "stages_applied": []
        }
        
        processed = audio.copy()
        
        # 1. RNNoise (si disponible et activé)
        if self.use_rnnoise and self.rnnoise_reducer and self.rnnoise_reducer.available:
            processed = self.rnnoise_reducer.reduce_noise(processed, sample_rate)
            stats["stages_applied"].append("rnnoise")
        
        # 2. Spectral Gating
        if self.use_spectral:
            processed = self.spectral_reducer.reduce_noise(
                processed,
                sample_rate,
                noise_sample=noise_profile
            )
            stats["stages_applied"].append("spectral_gating")
        
        stats["final_rms"] = float(np.sqrt(np.mean(processed ** 2)))
        stats["noise_reduction_db"] = 20 * np.log10(
            stats["original_rms"] / (stats["final_rms"] + 1e-10)
        )
        
        return processed, stats


def reduce_noise_file(
    input_path: str,
    output_path: Optional[str] = None,
    strength: float = 0.75
) -> str:
    """
    Réduit le bruit d'un fichier audio
    
    Args:
        input_path: Chemin du fichier d'entrée
        output_path: Chemin de sortie (auto-généré si non fourni)
        strength: Force de la réduction (0.0 à 1.0)
        
    Returns:
        Chemin du fichier débruité
    """
    from pathlib import Path
    
    # Lecture du fichier
    audio, sr = sf.read(input_path)
    
    # Réduction de bruit
    reducer = AdvancedNoiseReducer(strength=strength)
    denoised, stats = reducer.process(audio, sr)
    
    # Chemin de sortie
    if output_path is None:
        p = Path(input_path)
        output_path = str(p.parent / f"{p.stem}_denoised{p.suffix}")
    
    # Sauvegarde
    sf.write(output_path, denoised, sr)
    
    print(f"✅ Fichier débruité: {output_path}")
    print(f"   Réduction: {stats['noise_reduction_db']:.1f} dB")
    print(f"   Étapes: {', '.join(stats['stages_applied'])}")
    
    return output_path


# CLI
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="🔇 Réduction de bruit audio")
    parser.add_argument("input", help="Fichier audio d'entrée")
    parser.add_argument("-o", "--output", help="Fichier de sortie")
    parser.add_argument("-s", "--strength", type=float, default=0.75,
                        help="Force de réduction (0.0-1.0)")
    
    args = parser.parse_args()
    reduce_noise_file(args.input, args.output, args.strength)
