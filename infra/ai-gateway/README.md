# Passerelle IA Notitia

Une seule API compatible OpenAI pour toute l'IA de l'app, basée sur
[LiteLLM](https://github.com/BerriAI/litellm) (open source, MIT).

```
App Flutter ──► Passerelle (LiteLLM) ──► DeepInfra (modèles open source, payé au token)
 clé virtuelle    clés par personne,        plafond de dépense côté DeepInfra
 plafonnée        budgets, logs, fallback   + Brave Search pour les sources web
```

La passerelle ne fait **aucun calcul IA** : elle relaie. Elle tourne donc sur
n'importe quel PC ou petit VPS (2 vCPU / 2–4 Go de RAM suffisent).

## Modèles (alias utilisés par l'app)

| Alias | Modèle | Usage | $ / 1M tokens (entrée → sortie) |
|---|---|---|---|
| `notitia-fast` | Mistral Small 3.2 24B | correction, titres | 0,075 → 0,20 |
| `notitia-smart` | DeepSeek V4 Flash | assistant, résumé enrichi, mind map standard | 0,09 → 0,18 |
| `notitia-premium` | Kimi K2.6 | mind map premium | 0,75 → 3,50 |
| `notitia-fallback` | Qwen3.5 35B A3B | secours automatique | 0,14 → 1,00 |
| `notitia-embed` | Qwen3-Embedding 8B (1024 dims) | recherche sémantique | 0,01 |
| `brave-search` | Brave Search API | sources web du résumé | 5 $ offerts / mois |

Changer de modèle = modifier `config.yaml` puis `docker compose restart litellm`.
**Aucune mise à jour de l'app n'est nécessaire.**

---

## 1. Démarrer (PC ou serveur)

Prérequis : Docker + Docker Compose (`docker compose` ou `docker-compose`).

```bash
cd infra/ai-gateway
cp .env.example .env
# Remplir .env :
#   LITELLM_MASTER_KEY  → echo "sk-$(openssl rand -hex 24)"
#   POSTGRES_PASSWORD   → openssl rand -hex 24
#   DEEPINFRA_API_KEY, BRAVE_API_KEY, UI_PASSWORD
docker compose up -d
```

Premier démarrage ≈ 1 min (création de la base). Vérifier :

```bash
curl http://localhost:4000/health/liveliness     # → "I'm alive!"
./scripts/smoke-test.sh                          # teste chaque modèle + la recherche
```

## 2. Créer les clés

Ne jamais mettre la `LITELLM_MASTER_KEY` dans l'app. On crée des clés
virtuelles plafonnées :

```bash
./scripts/create-key.sh app-demo 3 30        # clé de l'app : 3 $/30 j, 30 req/min
./scripts/create-key.sh dev-alexandre 2 60   # une clé par membre de l'équipe
```

Si une clé fuite, la perte maximale est son budget. On peut la révoquer depuis
l'interface d'admin : `http://<hôte>:4000/ui` (identifiants `UI_USERNAME` /
`UI_PASSWORD`), qui affiche aussi les coûts par clé et par modèle.

## 3. Brancher l'app Flutter

```bash
cp env/ai.example.json env/ai.json   # à la racine du projet, jamais commité
```

```json
{
  "AI_BASE_URL": "http://<adresse>:4000",
  "AI_API_KEY": "sk-...clé app-demo...",
  "DEEPGRAM_API_KEY": "..."
}
```

```bash
flutter run --dart-define-from-file=env/ai.json
```

Quelle `AI_BASE_URL` mettre ?

| Situation | AI_BASE_URL |
|---|---|
| App desktop/web sur le même PC | `http://localhost:4000` |
| Émulateur Android | `http://10.0.2.2:4000` |
| Téléphone sur le même Wi-Fi que le PC | `http://<IP locale du PC>:4000` (`hostname -I`) |
| Démo depuis n'importe où (PC allumé) | URL du tunnel, voir ci-dessous |
| VPS avec domaine | `https://notitia-ai.duckdns.org` |

> Le HTTP en clair vers une IP locale fonctionne sur Android (`usesCleartextTraffic`
> est activé) et sur iOS (ATS ne s'applique pas aux adresses IP). Dès que l'app sort
> du Wi-Fi local, utiliser le tunnel ou le VPS (HTTPS).

## 4. Démo accessible partout depuis le PC (sans VPS)

```bash
docker compose --profile tunnel up -d
docker compose logs tunnel | grep trycloudflare
# → https://xxxx-xxxx.trycloudflare.com  (à mettre dans AI_BASE_URL)
```

Gratuit, HTTPS, sans compte. L'URL change à chaque redémarrage du tunnel.

## 5. Passer sur un VPS (quand il est disponible)

1. Ubuntu 24.04, installer Docker : `curl -fsSL https://get.docker.com | sh`
2. Créer un sous-domaine gratuit sur [duckdns.org](https://www.duckdns.org) pointant vers l'IP du VPS
3. `git clone` du dépôt, puis dans `infra/ai-gateway/.env` :
   `DOMAIN=notitia-ai.duckdns.org` et `LITELLM_BIND=127.0.0.1`
4. Ouvrir les ports 80 et 443 (pare-feu du fournisseur)
5. `docker compose --profile https up -d` — Caddy obtient le certificat HTTPS tout seul
6. Recréer les clés (`create-key.sh`) puis mettre `AI_BASE_URL=https://notitia-ai.duckdns.org`
7. Surveillance gratuite : [UptimeRobot](https://uptimerobot.com) sur `https://<domaine>/health/liveliness`

## Budget

Plafond de dépense DeepInfra (réglé dans leur console) + budget par clé ici.
Ordre de grandeur : ~2 000 générations ≈ 1 $ avec `notitia-smart`.

## Dépannage

| Symptôme | Cause probable |
|---|---|
| `Invalid proxy server token` | mauvaise `AI_API_KEY` dans `env/ai.json` |
| `User is not authorized to access this resource` | `DEEPINFRA_API_KEY` invalide dans `.env` |
| `SUBSCRIPTION_TOKEN_INVALID` | `BRAVE_API_KEY` invalide (le résumé marche, sans sources) |
| `Budget exceeded` | budget de la clé atteint → `create-key.sh` ou l'UI |
| L'app n'arrive pas à joindre la passerelle | mauvaise IP / pas le même Wi-Fi / pare-feu du PC (port 4000) |
