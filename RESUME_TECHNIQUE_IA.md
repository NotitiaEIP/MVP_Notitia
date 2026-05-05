# Notitia MVP — Résumé technique (architecture & IA)

## Vue d’ensemble

Notitia est une application **Flutter/Dart multiplateforme** (Android, iOS, Web, Desktop) pour la prise de notes vocales, la transcription, la correction intelligente et la recherche assistée par IA.

Le projet est organisé en deux blocs :

1. **Frontend Flutter** (`lib/`) : UI, orchestration, stockage local, appels APIs IA.
2. **Backend Python optionnel** (`ia_python/`) : API Flask locale pour pipeline Whisper + Mistral + réduction de bruit.

---

## Architecture applicative

- **Entrée app** : `lib/main.dart`
- **Pages principales** : `lib/pages/`
  - `capture_page.dart` (capture audio + transcription)
  - `edit_page.dart` (édition + correction)
  - `assistant_page.dart` / `search_page.dart` (assistant & recherche)
  - `history_page.dart`, `meeting_page.dart`, `mind_map_page.dart`
- **Services métier** : `lib/services/`
  - STT temps réel : `deepgram_service.dart`
  - Correction LLM : `mistral_service.dart`
  - Embeddings + génération : `gemini_service.dart`
  - Orchestration RAG : `rag_service.dart`
  - Base vectorielle locale : `vector_store_service.dart`
  - Alternative LLM : `claude_service.dart`
  - Persistance locale : `storage_service.dart`
- **Backend IA Python (optionnel)** : `ia_python/`
  - API : `notitia_api.py`
  - STT local : `notitia_stt.py` (Faster-Whisper)
  - Correction Mistral : `mistral_integration.py`
  - Fusion Whisper+Mistral : `fusion_system.py`
  - Réduction de bruit : `noise_reduction.py`

---

## IA utilisées : rôle et objectif

| IA / Service | Où dans le code | Rôle dans le produit | Entrées / sorties |
|---|---|---|---|
| **Deepgram (Nova-3)** | `lib/services/deepgram_service.dart` | Transcription vocale **temps réel** via WebSocket | Entrée: flux audio PCM 16kHz • Sortie: texte partiel/final + confiance |
| **Speech-to-Text natif** | `lib/pages/capture_page.dart` | Fallback local de transcription (OS) | Entrée: micro • Sortie: texte transcrit |
| **Faster-Whisper (local Python)** | `ia_python/notitia_stt.py` + `ia_python/notitia_api.py` | STT local haute précision (pipeline backend optionnel) | Entrée: fichier/base64/PCM • Sortie: segments, mots, timestamps, confiance |
| **Mistral AI** | `lib/services/mistral_service.dart` et `ia_python/mistral_integration.py` | Correction/amélioration de transcription (orthographe, ponctuation, reformulation selon niveau) | Entrée: texte brut • Sortie: texte corrigé |
| **Google Gemini (Embedding + Gen)** | `lib/services/gemini_service.dart` | Génération d’embeddings et réponses assistant | Entrée: texte/question+contexte • Sortie: vecteur embedding + réponse générée |
| **RAG local (Gemini + Vector Store)** | `lib/services/rag_service.dart` + `vector_store_service.dart` | Recherche sémantique dans l’historique et réponses contextualisées | Entrée: question utilisateur • Sortie: top chunks similaires + réponse |
| **Claude (Anthropic)** | `lib/services/claude_service.dart` | Alternative LLM disponible (non centrale dans le flux principal) | Entrée: prompt • Sortie: réponse texte/JSON |
| **Réduction de bruit (RNNoise/noisereduce)** | `ia_python/noise_reduction.py` | Nettoyage audio avant transcription (backend local) | Entrée: signal audio • Sortie: audio débruité |

---

## Flux technique principal

1. L’utilisateur enregistre sa voix depuis `capture_page.dart`.
2. Transcription en direct via **Deepgram** (ou fallback natif / backend Whisper selon le mode).
3. Le texte peut être amélioré via **Mistral** (`correctTranscription`).
4. Sauvegarde locale des transcriptions (`storage_service.dart`).
5. Indexation RAG :
   - découpage en chunks,
   - embeddings via **Gemini**,
   - stockage vectoriel local JSON (`notitia_vectors.json`).
6. Dans l’assistant, une question est embedée, les chunks proches sont récupérés, puis **Gemini** génère une réponse contextualisée.

---

## Stack technique

- **Frontend** : Flutter, Dart, `http`, `web_socket_channel`, `record`, `speech_to_text`, `supabase_flutter`.
- **Backend IA local (optionnel)** : Python, Flask, Faster-Whisper, Mistral client, scipy/soundfile/noisereduce.
- **Persistance** : JSON local (transcriptions + vecteurs), Supabase optionnel pour auth/data.

---

## Points d’attention techniques

- Des clés API sont actuellement présentes en dur dans certains services (`deepgram_service.dart`, `mistral_service.dart`, `gemini_service.dart`, `claude_service.dart`).
- Le vector store actuel est un stockage JSON local (adapté MVP, moins adapté à grande échelle).
- Le pipeline principal combine plusieurs appels IA (STT + correction + RAG), ce qui impacte latence/coût selon l’usage.

