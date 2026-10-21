# Point de départ — le prototype Notitia (février → mai 2026)

## Notitia en une phrase

Application de **prise de notes vocale** : on parle, Notitia transcrit, corrige,
résume et permet de **retrouver ses conversations** en posant des questions.

## Ce que fait le prototype

- 🎙️ Transcription en temps réel (Deepgram Nova-3, repli sur la reco vocale du téléphone)
- ✍️ Correction automatique + titre généré par IA
- 🤖 Assistant mémoire : questions sur l'historique (RAG)
- 🧠 Mind maps générées depuis une ou plusieurs transcriptions
- 📰 Résumé enrichi : sections, graphiques, chiffres clés, sources web
- 👥 Mode réunion, tags et filtres, historique
- 📱 Widget, Live Activities iOS, partage NFC / QR code
- 🔐 Comptes Supabase (email OTP, Google), suppression de compte
- 🪼 Mascotte « Meduza », onboarding, FR / EN

## Chronologie

| Période | Étapes |
|---|---|
| Février 2026 | App Flutter : transcription, sauvegarde, recherche simple, identité visuelle |
| Mars 2026 | Assistant IA, mind map, login Supabase, mascotte, app iOS, onboarding, réunions, multilingue, navigation |
| Mai 2026 | Résumé enrichi depuis l'historique, documentation technique |

## Stack technique du prototype

- **App** : Flutter (iOS, Android, web, desktop), stockage local JSON, Supabase
- **IA** : Google Gemini (embeddings + génération), Claude (mind map premium),
  Mistral API (correction), Deepgram (transcription)
- **Backend optionnel** : Python (Faster-Whisper, réduction de bruit)

> 🎤 Le prototype fonctionnait, mais toute l'IA reposait sur des API propriétaires
> avec des clés écrites dans le code — c'est le point de départ de la période suivante.
