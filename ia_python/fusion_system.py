#!/usr/bin/env python3
"""
🔄 Notitia Edge - Système de Fusion Intelligente
Combine Whisper + Mistral pour une transcription optimale

Architecture:
1. Whisper transcrit l'audio → Texte brut
2. Mistral analyse et améliore → Texte corrigé
3. Fusion intelligente → Texte final avec confiance

Le système ne fait pas juste "corriger" mais vraiment FUSIONNER
les capacités des deux IA pour un résultat optimal.
"""

import os
import json
import re
from typing import Optional, Dict, Any, List, Tuple
from dataclasses import dataclass, field
from difflib import SequenceMatcher

import numpy as np

# Imports locaux
try:
    from mistralai import Mistral
except ImportError:
    os.system("pip install mistralai")
    from mistralai import Mistral

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


@dataclass
class FusionResult:
    """Résultat de la fusion Whisper + Mistral"""
    whisper_text: str
    mistral_text: str
    final_text: str
    confidence: float
    changes: List[Dict[str, Any]]
    word_analysis: List[Dict[str, Any]]
    metadata: Dict[str, Any]


class WhisperMistralFusion:
    """
    🔄 Système de Fusion Intelligente Whisper + Mistral
    
    Au lieu de simplement "corriger", ce système:
    1. Analyse les segments où Whisper hésite (faible probabilité)
    2. Demande à Mistral de proposer des alternatives contextuelles
    3. Fusionne intelligemment en prenant le meilleur des deux
    4. Garde trace des modifications avec niveau de confiance
    """
    
    FUSION_PROMPT = """Tu es un expert en analyse linguistique et correction de transcriptions audio.

CONTEXTE: Tu reçois une transcription automatique (Whisper) avec des mots et leurs scores de confiance.

MISSION: Analyser chaque mot et proposer des corrections UNIQUEMENT quand nécessaire.

RÈGLES STRICTES:
1. Pour les mots avec confiance > 0.85: NE PAS modifier sauf erreur évidente
2. Pour les mots avec confiance 0.60-0.85: Vérifier le contexte et corriger si nécessaire
3. Pour les mots avec confiance < 0.60: Proposer le mot le plus probable selon le contexte
4. Toujours respecter le sens global de la phrase
5. Les noms propres peuvent avoir une faible confiance mais être corrects

FORMAT DE RÉPONSE (JSON strict):
{
    "corrections": [
        {
            "original": "mot original",
            "corrected": "mot corrigé",
            "reason": "raison courte",
            "confidence": 0.95
        }
    ],
    "full_text": "texte complet corrigé"
}

Réponds UNIQUEMENT avec le JSON, sans explication."""

    CONTEXT_ANALYSIS_PROMPT = """Analyse cette transcription et identifie:
1. Le sujet principal
2. Le registre de langue (formel, informel, technique)
3. Les entités mentionnées (personnes, lieux, organisations)
4. Le domaine (médical, juridique, tech, quotidien, etc.)

Réponds en JSON:
{
    "subject": "sujet",
    "register": "registre",
    "entities": ["entité1", "entité2"],
    "domain": "domaine",
    "vocabulary_hints": ["mot technique 1", "mot technique 2"]
}"""

    def __init__(self, api_key: Optional[str] = None, model: str = "mistral-small-latest"):
        """
        Initialise le système de fusion
        
        Args:
            api_key: Clé API Mistral (utilise .env si non fourni)
            model: Modèle Mistral à utiliser
        """
        self.api_key = api_key or os.getenv("MISTRAL_API_KEY", "")
        self.model = model
        self.client = None
        
        if self.api_key and self.api_key != "your_mistral_api_key_here":
            try:
                self.client = Mistral(api_key=self.api_key)
                print("✅ Fusion Whisper+Mistral initialisée")
            except Exception as e:
                print(f"⚠️ Erreur Mistral: {e}")
    
    @property
    def available(self) -> bool:
        return self.client is not None
    
    def analyze_context(self, text: str) -> Dict[str, Any]:
        """Analyse le contexte de la transcription pour améliorer les corrections"""
        if not self.client:
            return {}
        
        try:
            response = self.client.chat.complete(
                model=self.model,
                messages=[
                    {"role": "system", "content": self.CONTEXT_ANALYSIS_PROMPT},
                    {"role": "user", "content": f"Transcription:\n{text}"}
                ],
                temperature=0.1,
                max_tokens=500
            )
            
            content = response.choices[0].message.content.strip()
            if content.startswith("```"):
                content = re.sub(r"```json?\n?", "", content).rstrip("`")
            
            return json.loads(content)
        except:
            return {}
    
    def fuse_transcription(
        self,
        whisper_result: Dict[str, Any],
        context_hint: Optional[str] = None
    ) -> FusionResult:
        """
        Fusionne la transcription Whisper avec l'analyse Mistral
        
        Args:
            whisper_result: Résultat de NotitiaSTT.transcribe_file()
            context_hint: Indice sur le contexte (optionnel)
            
        Returns:
            FusionResult avec le texte optimisé
        """
        whisper_text = whisper_result.get("full_text", "")
        words = whisper_result.get("words", [])
        
        # Si pas de Mistral ou texte vide, retourne l'original
        if not self.client or not whisper_text.strip():
            return FusionResult(
                whisper_text=whisper_text,
                mistral_text=whisper_text,
                final_text=whisper_text,
                confidence=1.0,
                changes=[],
                word_analysis=[],
                metadata={"fusion_applied": False}
            )
        
        # 1. Analyse du contexte
        context = self.analyze_context(whisper_text)
        
        # 2. Préparation des mots avec confiance pour Mistral
        words_with_confidence = self._format_words_for_analysis(words)
        
        # 3. Demande de correction à Mistral
        corrections = self._get_mistral_corrections(
            whisper_text,
            words_with_confidence,
            context,
            context_hint
        )
        
        # 4. Fusion intelligente
        final_text, changes = self._apply_fusion(
            whisper_text,
            words,
            corrections
        )
        
        # 5. Calcul de la confiance globale
        confidence = self._calculate_confidence(words, changes)
        
        return FusionResult(
            whisper_text=whisper_text,
            mistral_text=corrections.get("full_text", whisper_text),
            final_text=final_text,
            confidence=confidence,
            changes=changes,
            word_analysis=self._analyze_word_changes(words, corrections),
            metadata={
                "fusion_applied": True,
                "context": context,
                "model": self.model,
                "total_words": len(words),
                "words_modified": len(changes)
            }
        )
    
    def _format_words_for_analysis(self, words: List[Dict]) -> str:
        """Formate les mots avec leur confiance pour l'analyse"""
        if not words:
            return ""
        
        lines = []
        for w in words:
            word = w.get("word", "").strip()
            prob = w.get("probability", 1.0)
            if word:
                lines.append(f"'{word}' (confiance: {prob:.2f})")
        
        return "\n".join(lines)
    
    def _get_mistral_corrections(
        self,
        text: str,
        words_analysis: str,
        context: Dict,
        context_hint: Optional[str]
    ) -> Dict[str, Any]:
        """Obtient les corrections de Mistral"""
        # Construction du prompt enrichi
        prompt_parts = [f"TRANSCRIPTION:\n{text}\n"]
        
        if words_analysis:
            prompt_parts.append(f"\nANALYSE DES MOTS:\n{words_analysis}\n")
        
        if context:
            prompt_parts.append(f"\nCONTEXTE DÉTECTÉ:")
            prompt_parts.append(f"- Domaine: {context.get('domain', 'général')}")
            prompt_parts.append(f"- Registre: {context.get('register', 'standard')}")
            if context.get('vocabulary_hints'):
                prompt_parts.append(f"- Vocabulaire probable: {', '.join(context['vocabulary_hints'])}")
        
        if context_hint:
            prompt_parts.append(f"\nINDICE UTILISATEUR: {context_hint}")
        
        user_message = "\n".join(prompt_parts)
        
        try:
            response = self.client.chat.complete(
                model=self.model,
                messages=[
                    {"role": "system", "content": self.FUSION_PROMPT},
                    {"role": "user", "content": user_message}
                ],
                temperature=0.1,
                max_tokens=2048
            )
            
            content = response.choices[0].message.content.strip()
            
            # Nettoyage du JSON
            if content.startswith("```"):
                content = re.sub(r"```json?\n?", "", content).rstrip("`")
            
            return json.loads(content)
            
        except json.JSONDecodeError:
            return {"corrections": [], "full_text": text}
        except Exception as e:
            print(f"⚠️ Erreur Mistral: {e}")
            return {"corrections": [], "full_text": text}
    
    def _apply_fusion(
        self,
        original_text: str,
        words: List[Dict],
        corrections: Dict
    ) -> Tuple[str, List[Dict]]:
        """Applique la fusion intelligente"""
        changes = []
        final_text = corrections.get("full_text", original_text)
        
        # Analyse des corrections proposées
        for corr in corrections.get("corrections", []):
            original = corr.get("original", "")
            corrected = corr.get("corrected", "")
            confidence = corr.get("confidence", 0.5)
            
            if original != corrected and confidence > 0.7:
                changes.append({
                    "original": original,
                    "corrected": corrected,
                    "reason": corr.get("reason", ""),
                    "confidence": confidence,
                    "applied": True
                })
        
        return final_text, changes
    
    def _calculate_confidence(
        self,
        words: List[Dict],
        changes: List[Dict]
    ) -> float:
        """Calcule la confiance globale de la transcription fusionnée"""
        if not words:
            return 1.0
        
        # Moyenne des probabilités Whisper
        whisper_confidence = sum(w.get("probability", 1.0) for w in words) / len(words)
        
        # Bonus pour les corrections Mistral à haute confiance
        if changes:
            mistral_confidence = sum(c.get("confidence", 0.5) for c in changes) / len(changes)
            # Combine les deux
            return 0.6 * whisper_confidence + 0.4 * mistral_confidence
        
        return whisper_confidence
    
    def _analyze_word_changes(
        self,
        words: List[Dict],
        corrections: Dict
    ) -> List[Dict]:
        """Analyse détaillée des changements par mot"""
        analysis = []
        correction_map = {
            c["original"]: c
            for c in corrections.get("corrections", [])
        }
        
        for w in words:
            word = w.get("word", "").strip()
            prob = w.get("probability", 1.0)
            
            entry = {
                "word": word,
                "whisper_confidence": prob,
                "modified": word in correction_map,
            }
            
            if word in correction_map:
                corr = correction_map[word]
                entry["corrected_to"] = corr.get("corrected", word)
                entry["mistral_confidence"] = corr.get("confidence", 0.5)
                entry["reason"] = corr.get("reason", "")
            
            analysis.append(entry)
        
        return analysis


class NotitiaFusionSTT:
    """
    🎯 Moteur STT complet avec Fusion Intelligente
    
    Combine:
    - Réduction de bruit avancée
    - Transcription Whisper
    - Fusion Mistral intelligente
    """
    
    def __init__(
        self,
        whisper_model: str = "base",
        language: str = "fr",
        enable_noise_reduction: bool = True,
        enable_fusion: bool = True,
        noise_strength: float = 0.75
    ):
        from notitia_stt import NotitiaSTT
        from noise_reduction import AdvancedNoiseReducer
        
        self.stt = NotitiaSTT(model_size=whisper_model, language=language)
        self.fusion = WhisperMistralFusion() if enable_fusion else None
        self.noise_reducer = AdvancedNoiseReducer(strength=noise_strength) if enable_noise_reduction else None
        
        self.enable_noise_reduction = enable_noise_reduction
        self.enable_fusion = enable_fusion and (self.fusion is not None and self.fusion.available)
    
    def transcribe_file(
        self,
        audio_path: str,
        context_hint: Optional[str] = None,
        enhance_audio: bool = True,
        word_timestamps: bool = True
    ) -> Dict[str, Any]:
        """
        Transcription complète avec tous les traitements
        
        Args:
            audio_path: Chemin du fichier audio
            context_hint: Indice sur le contexte (ex: "réunion médicale")
            enhance_audio: Appliquer l'amélioration audio de base
            word_timestamps: Inclure les timestamps par mot
            
        Returns:
            Dictionnaire avec transcription et métadonnées
        """
        import soundfile as sf
        import numpy as np
        from scipy.signal import resample
        
        # 1. Lecture de l'audio
        audio, sr = sf.read(audio_path)
        
        # Mono si stéréo
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)
        
        # 2. Réduction de bruit
        noise_stats = {}
        if self.enable_noise_reduction and self.noise_reducer:
            audio, noise_stats = self.noise_reducer.process(audio, sr)
        
        # 3. Resample à 16kHz pour Whisper
        if sr != 16000:
            n_samples = int(len(audio) * 16000 / sr)
            audio = resample(audio, n_samples).astype(np.float32)
            sr = 16000
        
        # 4. Transcription Whisper
        whisper_result = self.stt.transcribe_array(
            audio, sr,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        
        # 5. Fusion Mistral
        if self.enable_fusion and self.fusion:
            fusion_result = self.fusion.fuse_transcription(
                whisper_result,
                context_hint=context_hint
            )
            
            # Enrichissement du résultat
            result = whisper_result.copy()
            result["original_text"] = fusion_result.whisper_text
            result["full_text"] = fusion_result.final_text
            result["fusion"] = {
                "applied": True,
                "confidence": fusion_result.confidence,
                "changes": fusion_result.changes,
                "word_analysis": fusion_result.word_analysis,
                "metadata": fusion_result.metadata
            }
        else:
            result = whisper_result
            result["fusion"] = {"applied": False}
        
        # Ajout des stats de réduction de bruit
        result["noise_reduction"] = noise_stats
        
        return result
    
    def transcribe_realtime(
        self,
        audio_chunk: np.ndarray,
        sample_rate: int = 16000,
        context_hint: Optional[str] = None
    ) -> Dict[str, Any]:
        """Transcription temps réel d'un chunk audio"""
        # Réduction de bruit rapide
        if self.enable_noise_reduction and self.noise_reducer:
            audio_chunk, _ = self.noise_reducer.process(audio_chunk, sample_rate)
        
        # Transcription
        result = self.stt.transcribe_array(
            audio_chunk, sample_rate,
            enhance_audio=True,
            word_timestamps=True
        )
        
        # Fusion (simplifiée pour le temps réel)
        if self.enable_fusion and self.fusion and result.get("full_text"):
            fusion_result = self.fusion.fuse_transcription(result, context_hint)
            result["original_text"] = fusion_result.whisper_text
            result["full_text"] = fusion_result.final_text
            result["fusion"] = {"applied": True, "confidence": fusion_result.confidence}
        
        return result


# ============================================================================
# CLI
# ============================================================================

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="🔄 Notitia Fusion STT")
    parser.add_argument("--file", "-f", required=True, help="Fichier audio")
    parser.add_argument("--context", "-c", help="Contexte (ex: 'réunion technique')")
    parser.add_argument("--no-noise", action="store_true", help="Désactiver la réduction de bruit")
    parser.add_argument("--no-fusion", action="store_true", help="Désactiver la fusion Mistral")
    parser.add_argument("--model", "-m", default="base", help="Modèle Whisper")
    parser.add_argument("--output", "-o", help="Fichier de sortie JSON")
    
    args = parser.parse_args()
    
    # Initialisation
    stt = NotitiaFusionSTT(
        whisper_model=args.model,
        enable_noise_reduction=not args.no_noise,
        enable_fusion=not args.no_fusion
    )
    
    # Transcription
    print(f"\n🎤 Transcription de: {args.file}")
    if args.context:
        print(f"📝 Contexte: {args.context}")
    
    result = stt.transcribe_file(args.file, context_hint=args.context)
    
    # Affichage
    print(f"\n{'='*60}")
    
    if result.get("original_text"):
        print(f"📝 WHISPER (original):\n{result['original_text']}")
        print(f"\n✨ FUSION (corrigé):\n{result['full_text']}")
    else:
        print(f"📝 TRANSCRIPTION:\n{result['full_text']}")
    
    if result.get("fusion", {}).get("applied"):
        fusion = result["fusion"]
        print(f"\n📊 FUSION:")
        print(f"   Confiance: {fusion['confidence']:.1%}")
        print(f"   Mots modifiés: {len(fusion.get('changes', []))}")
        
        for change in fusion.get("changes", [])[:5]:
            print(f"   • '{change['original']}' → '{change['corrected']}' ({change.get('reason', '')})")
    
    if result.get("noise_reduction"):
        nr = result["noise_reduction"]
        if nr.get("noise_reduction_db"):
            print(f"\n🔇 Réduction de bruit: {nr['noise_reduction_db']:.1f} dB")
    
    # Sauvegarde
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"\n💾 Sauvegardé: {args.output}")


if __name__ == "__main__":
    main()
