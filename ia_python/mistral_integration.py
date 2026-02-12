#!/usr/bin/env python3
"""
🤖 Notitia Edge - Intégration Mistral AI
Module de correction et amélioration des transcriptions via Mistral AI
"""

import os
import json
import re
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field
from enum import Enum

# Chargement des variables d'environnement
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Client Mistral
try:
    from mistralai import Mistral
except ImportError:
    print("⚠️ Installation du client Mistral...")
    os.system("pip install mistralai")
    from mistralai import Mistral


class CorrectionLevel(Enum):
    """Niveaux de correction disponibles"""
    LIGHT = "light"      # Orthographe seulement
    MEDIUM = "medium"    # + Ponctuation et grammaire
    FULL = "full"        # + Restructuration


@dataclass
class MistralConfig:
    """Configuration pour l'API Mistral"""
    api_key: str = ""
    model: str = "mistral-small-latest"
    correction_level: CorrectionLevel = CorrectionLevel.MEDIUM
    temperature: float = 0.1  # Basse pour plus de précision
    max_tokens: int = 4096
    
    @classmethod
    def from_env(cls) -> "MistralConfig":
        """Charge la configuration depuis les variables d'environnement"""
        level_str = os.getenv("CORRECTION_LEVEL", "medium").lower()
        try:
            level = CorrectionLevel(level_str)
        except ValueError:
            level = CorrectionLevel.MEDIUM
        
        return cls(
            api_key=os.getenv("MISTRAL_API_KEY", ""),
            model=os.getenv("MISTRAL_MODEL", "mistral-small-latest"),
            correction_level=level
        )
    
    @classmethod
    def from_file(cls, path: str = ".env") -> "MistralConfig":
        """Charge la configuration depuis un fichier"""
        config = {}
        if os.path.exists(path):
            with open(path, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        config[key.strip()] = value.strip()
        
        level_str = config.get("CORRECTION_LEVEL", "medium").lower()
        try:
            level = CorrectionLevel(level_str)
        except ValueError:
            level = CorrectionLevel.MEDIUM
        
        return cls(
            api_key=config.get("MISTRAL_API_KEY", ""),
            model=config.get("MISTRAL_MODEL", "mistral-small-latest"),
            correction_level=level
        )


class MistralCorrector:
    """
    🤖 Correcteur de transcription basé sur Mistral AI
    
    Utilise les modèles Mistral pour:
    - Corriger les erreurs de transcription
    - Améliorer la ponctuation
    - Compléter les mots mal captés
    - Reformuler si nécessaire
    """
    
    # Prompts système pour chaque niveau de correction
    SYSTEM_PROMPTS = {
        CorrectionLevel.LIGHT: """Tu es un assistant spécialisé dans la correction de transcriptions audio.

RÈGLES STRICTES:
1. Corrige UNIQUEMENT les fautes d'orthographe évidentes
2. NE MODIFIE PAS la structure des phrases
3. NE CHANGE PAS les mots sauf s'ils sont clairement mal orthographiés
4. Garde le texte aussi proche que possible de l'original
5. Réponds UNIQUEMENT avec le texte corrigé, sans explication""",

        CorrectionLevel.MEDIUM: """Tu es un assistant expert en correction de transcriptions audio.

RÈGLES:
1. Corrige les fautes d'orthographe
2. Ajoute la ponctuation appropriée (points, virgules, points d'interrogation)
3. Corrige les erreurs de grammaire évidentes
4. Si un mot semble mal transcrit, devine le mot correct selon le contexte
5. Garde le sens et le style de l'original
6. Réponds UNIQUEMENT avec le texte corrigé, sans explication

INDICES COURANTS D'ERREURS DE TRANSCRIPTION:
- Homophones confondus (a/à, et/est, ou/où, ce/se)
- Mots coupés ou fusionnés
- Noms propres mal orthographiés
- Chiffres mal transcrits""",

        CorrectionLevel.FULL: """Tu es un assistant expert en amélioration de transcriptions audio.

RÈGLES:
1. Corrige toutes les fautes d'orthographe et de grammaire
2. Ajoute une ponctuation correcte et naturelle
3. Restructure les phrases si elles sont confuses
4. Devine et corrige les mots mal transcrits selon le contexte
5. Améliore la clarté tout en préservant le sens original
6. Supprime les hésitations (euh, hum) et répétitions inutiles
7. Garde un style naturel et conversationnel
8. Réponds UNIQUEMENT avec le texte corrigé, sans explication

INDICES COURANTS D'ERREURS DE TRANSCRIPTION:
- Homophones confondus
- Mots coupés ou fusionnés
- Noms propres mal orthographiés
- Chiffres mal transcrits
- Termes techniques déformés"""
    }
    
    def __init__(self, config: Optional[MistralConfig] = None):
        """
        Initialise le correcteur Mistral
        
        Args:
            config: Configuration Mistral (charge depuis .env si non fourni)
        """
        self.config = config or MistralConfig.from_env()
        
        if not self.config.api_key:
            raise ValueError(
                "❌ Clé API Mistral manquante!\n"
                "Créez un fichier .env avec: MISTRAL_API_KEY=votre_clé\n"
                "Obtenez votre clé sur: https://console.mistral.ai/api-keys"
            )
        
        self.client = Mistral(api_key=self.config.api_key)
        print(f"✅ Mistral AI initialisé (modèle: {self.config.model})")
    
    def correct_text(
        self,
        text: str,
        context: Optional[str] = None,
        level: Optional[CorrectionLevel] = None
    ) -> str:
        """
        Corrige un texte transcrit
        
        Args:
            text: Texte à corriger
            context: Contexte optionnel (sujet de la conversation, etc.)
            level: Niveau de correction (utilise celui de la config si non spécifié)
            
        Returns:
            Texte corrigé
        """
        if not text or not text.strip():
            return text
        
        level = level or self.config.correction_level
        system_prompt = self.SYSTEM_PROMPTS[level]
        
        # Ajout du contexte si fourni
        user_message = f"Corrige cette transcription:\n\n{text}"
        if context:
            user_message = f"Contexte: {context}\n\n{user_message}"
        
        try:
            response = self.client.chat.complete(
                model=self.config.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message}
                ],
                temperature=self.config.temperature,
                max_tokens=self.config.max_tokens
            )
            
            corrected = response.choices[0].message.content.strip()
            return corrected
            
        except Exception as e:
            print(f"⚠️ Erreur Mistral: {e}")
            return text  # Retourne l'original en cas d'erreur
    
    def correct_transcription_result(
        self,
        result: Dict[str, Any],
        context: Optional[str] = None,
        level: Optional[CorrectionLevel] = None
    ) -> Dict[str, Any]:
        """
        Corrige un résultat de transcription complet
        
        Args:
            result: Dictionnaire de résultat de NotitiaSTT
            context: Contexte optionnel
            level: Niveau de correction
            
        Returns:
            Résultat avec texte corrigé
        """
        # Copie du résultat
        corrected_result = result.copy()
        
        # Correction du texte complet
        if "full_text" in result:
            corrected_result["full_text"] = self.correct_text(
                result["full_text"],
                context=context,
                level=level
            )
            corrected_result["original_text"] = result["full_text"]
        
        # Correction des segments individuels
        if "segments" in result:
            corrected_segments = []
            for segment in result["segments"]:
                corrected_seg = segment.copy()
                corrected_seg["text"] = self.correct_text(
                    segment["text"],
                    context=context,
                    level=level
                )
                corrected_seg["original_text"] = segment["text"]
                corrected_segments.append(corrected_seg)
            corrected_result["segments"] = corrected_segments
        
        corrected_result["mistral_corrected"] = True
        corrected_result["correction_level"] = (level or self.config.correction_level).value
        
        return corrected_result
    
    def complete_missing_words(
        self,
        text: str,
        audio_quality_hint: str = "normal"
    ) -> str:
        """
        Tente de compléter les mots manquants ou mal transcrits
        
        Args:
            text: Texte avec potentiels mots manquants
            audio_quality_hint: Indication sur la qualité audio (low, normal, high)
            
        Returns:
            Texte avec mots complétés
        """
        system_prompt = """Tu es un expert en reconstruction de transcriptions audio dégradées.

MISSION: Reconstituer les mots manquants ou mal transcrits dans le texte.

RÈGLES:
1. Identifie les mots qui semblent incomplets ou incohérents
2. Devine le mot correct basé sur le contexte
3. Marque les mots très incertains avec [?]
4. Garde la structure originale
5. Réponds UNIQUEMENT avec le texte reconstitué"""

        quality_context = {
            "low": "L'audio était de mauvaise qualité avec beaucoup de bruit.",
            "normal": "L'audio était de qualité moyenne.",
            "high": "L'audio était de bonne qualité mais avec quelques passages inaudibles."
        }
        
        user_message = f"""Qualité audio: {quality_context.get(audio_quality_hint, quality_context['normal'])}

Transcription à reconstituer:
{text}"""
        
        try:
            response = self.client.chat.complete(
                model=self.config.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message}
                ],
                temperature=0.2,
                max_tokens=self.config.max_tokens
            )
            
            return response.choices[0].message.content.strip()
            
        except Exception as e:
            print(f"⚠️ Erreur Mistral: {e}")
            return text
    
    def extract_key_information(self, text: str) -> Dict[str, Any]:
        """
        Extrait les informations clés d'une transcription
        
        Args:
            text: Texte transcrit
            
        Returns:
            Dictionnaire avec les informations extraites
        """
        system_prompt = """Tu es un assistant d'extraction d'informations.

Analyse le texte et extrait les informations clés au format JSON:
{
    "summary": "Résumé en une phrase",
    "topics": ["liste", "des", "sujets"],
    "entities": {
        "persons": ["noms de personnes"],
        "places": ["lieux mentionnés"],
        "organizations": ["organisations"],
        "dates": ["dates mentionnées"],
        "numbers": ["chiffres importants"]
    },
    "sentiment": "positif/négatif/neutre",
    "action_items": ["actions à faire si mentionnées"],
    "questions": ["questions posées"]
}

Réponds UNIQUEMENT avec le JSON, sans explication."""

        try:
            response = self.client.chat.complete(
                model=self.config.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Analyse ce texte:\n\n{text}"}
                ],
                temperature=0.1,
                max_tokens=2048
            )
            
            content = response.choices[0].message.content.strip()
            # Nettoyage du JSON si nécessaire
            if content.startswith("```"):
                content = re.sub(r"```json?\n?", "", content)
                content = content.rstrip("`")
            
            return json.loads(content)
            
        except json.JSONDecodeError:
            return {"error": "Impossible de parser la réponse JSON"}
        except Exception as e:
            return {"error": str(e)}


class NotitiaSTTWithMistral:
    """
    🎯 Moteur STT Notitia avec correction Mistral intégrée
    
    Combine Faster-Whisper pour la transcription et Mistral pour la correction
    """
    
    def __init__(
        self,
        whisper_model: str = "base",
        language: str = "fr",
        mistral_config: Optional[MistralConfig] = None,
        enable_correction: bool = True
    ):
        """
        Initialise le moteur STT avec correction Mistral
        
        Args:
            whisper_model: Taille du modèle Whisper
            language: Langue par défaut
            mistral_config: Configuration Mistral
            enable_correction: Activer la correction automatique
        """
        # Import du moteur STT
        from notitia_stt import NotitiaSTT
        
        self.stt = NotitiaSTT(
            model_size=whisper_model,
            language=language
        )
        
        self.enable_correction = enable_correction
        self.corrector = None
        
        if enable_correction:
            try:
                self.corrector = MistralCorrector(mistral_config)
            except ValueError as e:
                print(f"⚠️ Correction Mistral désactivée: {e}")
                self.enable_correction = False
    
    def transcribe_file(
        self,
        audio_path: str,
        enhance_audio: bool = True,
        word_timestamps: bool = True,
        correct: bool = True,
        correction_level: Optional[CorrectionLevel] = None,
        context: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Transcrit un fichier avec correction optionnelle
        
        Args:
            audio_path: Chemin vers le fichier audio
            enhance_audio: Activer l'amélioration audio
            word_timestamps: Inclure les timestamps
            correct: Appliquer la correction Mistral
            correction_level: Niveau de correction
            context: Contexte pour améliorer la correction
            
        Returns:
            Résultat de transcription (corrigé si activé)
        """
        # Transcription de base
        result = self.stt.transcribe_file(
            audio_path,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        
        # Correction si activée
        if correct and self.enable_correction and self.corrector:
            result = self.corrector.correct_transcription_result(
                result,
                context=context,
                level=correction_level
            )
        
        return result
    
    def transcribe_array(
        self,
        audio,
        sample_rate: int = 16000,
        enhance_audio: bool = True,
        word_timestamps: bool = True,
        correct: bool = True,
        correction_level: Optional[CorrectionLevel] = None,
        context: Optional[str] = None
    ) -> Dict[str, Any]:
        """Transcrit un array numpy avec correction optionnelle"""
        result = self.stt.transcribe_array(
            audio,
            sample_rate=sample_rate,
            enhance_audio=enhance_audio,
            word_timestamps=word_timestamps
        )
        
        if correct and self.enable_correction and self.corrector:
            result = self.corrector.correct_transcription_result(
                result,
                context=context,
                level=correction_level
            )
        
        return result


# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

def test_mistral_connection(api_key: Optional[str] = None) -> bool:
    """
    Teste la connexion à l'API Mistral
    
    Args:
        api_key: Clé API (utilise .env si non fourni)
        
    Returns:
        True si la connexion fonctionne
    """
    try:
        key = api_key or os.getenv("MISTRAL_API_KEY")
        if not key:
            print("❌ Clé API non trouvée")
            return False
        
        client = Mistral(api_key=key)
        response = client.chat.complete(
            model="mistral-small-latest",
            messages=[{"role": "user", "content": "Dis juste 'OK'"}],
            max_tokens=10
        )
        
        print(f"✅ Connexion Mistral OK: {response.choices[0].message.content}")
        return True
        
    except Exception as e:
        print(f"❌ Erreur connexion Mistral: {e}")
        return False


def quick_correct(text: str, api_key: Optional[str] = None) -> str:
    """
    Correction rapide d'un texte
    
    Args:
        text: Texte à corriger
        api_key: Clé API optionnelle
        
    Returns:
        Texte corrigé
    """
    config = MistralConfig(
        api_key=api_key or os.getenv("MISTRAL_API_KEY", ""),
        correction_level=CorrectionLevel.MEDIUM
    )
    corrector = MistralCorrector(config)
    return corrector.correct_text(text)


# ============================================================================
# CLI
# ============================================================================

def main():
    """Point d'entrée CLI pour le module Mistral"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="🤖 Notitia - Correction Mistral AI"
    )
    parser.add_argument("--test", action="store_true",
                        help="Tester la connexion Mistral")
    parser.add_argument("--correct", "-c", type=str,
                        help="Texte à corriger")
    parser.add_argument("--file", "-f", type=str,
                        help="Fichier audio à transcrire et corriger")
    parser.add_argument("--level", "-l", default="medium",
                        choices=["light", "medium", "full"],
                        help="Niveau de correction")
    parser.add_argument("--context", type=str,
                        help="Contexte pour améliorer la correction")
    parser.add_argument("--extract", "-e", action="store_true",
                        help="Extraire les informations clés")
    
    args = parser.parse_args()
    
    if args.test:
        test_mistral_connection()
        return
    
    if args.correct:
        config = MistralConfig.from_env()
        config.correction_level = CorrectionLevel(args.level)
        corrector = MistralCorrector(config)
        
        corrected = corrector.correct_text(args.correct, context=args.context)
        print(f"\n📝 Original:\n{args.correct}")
        print(f"\n✨ Corrigé:\n{corrected}")
        
        if args.extract:
            info = corrector.extract_key_information(corrected)
            print(f"\n📊 Informations extraites:\n{json.dumps(info, indent=2, ensure_ascii=False)}")
        return
    
    if args.file:
        stt = NotitiaSTTWithMistral(
            whisper_model="base",
            enable_correction=True
        )
        
        result = stt.transcribe_file(
            args.file,
            correct=True,
            correction_level=CorrectionLevel(args.level),
            context=args.context
        )
        
        print(f"\n📝 Transcription originale:\n{result.get('original_text', 'N/A')}")
        print(f"\n✨ Transcription corrigée:\n{result['full_text']}")
        
        if args.extract and stt.corrector:
            info = stt.corrector.extract_key_information(result['full_text'])
            print(f"\n📊 Informations extraites:\n{json.dumps(info, indent=2, ensure_ascii=False)}")
        return
    
    parser.print_help()


if __name__ == "__main__":
    main()
