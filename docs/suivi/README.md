# Journal de bord — présentations toutes les 6 semaines

Ce dossier garde une trace de ce sur quoi on travaille, prête à transformer en
présentation (PPT) à chaque fin de période de 6 semaines.

## Fichiers

| Fichier | Contenu |
|---|---|
| `00_point-de-depart.md` | État du prototype avant les périodes suivies (fév. → mai 2026) |
| `periode_AAAA-MM-JJ.md` | Une période de 6 semaines, nommée par sa date de début |

## Convention (pour générer le PPT facilement)

- **1 titre `##` = 1 slide.** Le titre du fichier (`#`) = slide de titre.
- Uniquement des **infos clés** : puces courtes, tableaux, chiffres.
- `> 🎤` = notes pour l'oral (à mettre en notes du présentateur, pas sur la slide).
- Les schémas sont en **Mermaid** (rendus par GitHub, convertibles en image).
- Une période se met à jour au fil de l'eau : on ajoute, on ne réécrit pas l'historique.

## Générer la présentation

Donner le fichier de la période à une IA avec ce prompt :

> Génère une présentation de ~12 slides à partir de ce fichier. Chaque section `##`
> devient une slide, les lignes `> 🎤` vont dans les notes du présentateur, les
> tableaux restent des tableaux, le schéma Mermaid devient un diagramme. Style
> sobre, couleurs Notitia (bleu nuit `#001a33`, cyan néon, rose néon).
