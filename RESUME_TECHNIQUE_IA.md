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
  - Client IA unique (API compatible OpenAI) : `ai_client.dart` + config `lib/config/ai_config.dart`
  - Embeddings + génération (RAG, résumé enrichi) : `ai_service.dart`
  - Orchestration RAG : `rag_service.dart`
  - Base vectorielle locale : `vector_store_service.dart`
  - Correction + titres : `correction_service.dart` · Mind maps : `mind_map_service.dart`
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
| **Passerelle IA (LiteLLM)** | `infra/ai-gateway/` + `lib/services/ai_client.dart` | Point d'entrée unique vers les modèles open source (DeepInfra), clés plafonnées, fallback | Entrée: requêtes OpenAI-compatibles • Sortie: texte / JSON / vecteurs |
| **Mistral Small 3.2** (`notitia-fast`) | `lib/services/correction_service.dart` | Correction de transcription + titres | Entrée: texte brut • Sortie: texte corrigé |
| **DeepSeek V4 Flash** (`notitia-smart`) + **Qwen3-Embedding 8B** (`notitia-embed`) | `ai_service.dart`, `rag_service.dart`, `vector_store_service.dart`, `mind_map_service.dart` | Assistant RAG, résumé enrichi, mind map standard, recherche sémantique | Entrée: question/texte • Sortie: réponse, JSON, vecteurs 1024 dims |
| **Kimi K2.6** (`notitia-premium`) + **Brave Search** | `mind_map_service.dart`, `ai_service.dart` | Mind map premium · sources web du résumé (images : Openverse) | Entrée: transcriptions • Sortie: JSON / URLs |
| **Réduction de bruit (RNNoise/noisereduce)** | `ia_python/noise_reduction.py` | Nettoyage audio avant transcription (backend local) | Entrée: signal audio • Sortie: audio débruité |

---

## Flux technique principal

1. L’utilisateur enregistre sa voix depuis `capture_page.dart`.
2. Transcription en direct via **Deepgram** (ou fallback natif / backend Whisper selon le mode).
3. Le texte peut être amélioré via **Mistral** (`correctTranscription`).
4. Sauvegarde locale des transcriptions (`storage_service.dart`).
5. Indexation RAG :
   - découpage en chunks,
   - embeddings via **Qwen3-Embedding** (passerelle IA),
   - stockage vectoriel local JSON (`notitia_vectors.json`).
6. Dans l’assistant, une question est embedée, les chunks proches sont récupérés, puis **DeepSeek V4 Flash** génère une réponse contextualisée.

---

## Stack technique

- **Frontend** : Flutter, Dart, `http`, `web_socket_channel`, `record`, `speech_to_text`, `supabase_flutter`.
- **Backend IA local (optionnel)** : Python, Flask, Faster-Whisper, Mistral client, scipy/soundfile/noisereduce.
- **Passerelle IA** : LiteLLM (Docker) + Postgres, modèles open-weight via DeepInfra.
- **Persistance** : JSON local (transcriptions + vecteurs), Supabase optionnel pour auth/data.

---

## Points d’attention techniques

- Aucune clé dans le code : config injectée au build (`--dart-define-from-file=env/ai.json`), clés virtuelles plafonnées côté passerelle. Voir `infra/ai-gateway/README.md`.
- Le vector store actuel est un stockage JSON local (adapté MVP, moins adapté à grande échelle).
- Le pipeline principal combine plusieurs appels IA (STT + correction + RAG), ce qui impacte latence/coût selon l’usage.

