# Métadonnées App Store — Avert

Contenu prêt à coller dans App Store Connect (ou à pousser via `asc metadata`).
Une langue par dossier, un fichier par champ, longueurs respectées.

| Champ | Limite | FR | EN |
|---|---|---|---|
| Nom | 30 | `Avert` (5) | `Avert` |
| Sous-titre | 30 | `Repère les sites qui mentent` (28) | `Spots the sites that lie` (24) |
| Mots-clés | 100 | voir `keywords.txt` | voir `keywords.txt` |
| Texte promo | 170 | `promotional_text.txt` | idem |
| Description | 4000 | `description.txt` | idem |

- **Catégorie** : Utilitaires (primaire), Productivité (secondaire).
- **Âge** : 4+.
- **Prix** : gratuit, sans achat intégré, sans compte.
- **Confidentialité** : « Aucune donnée collectée » — `PrivacyInfo.xcprivacy` de
  l'app et de l'extension déclarent `NSPrivacyTracking = false` et aucune
  `CollectedDataType`. Ne rien cocher d'autre dans le questionnaire ASC.
- **URL de confidentialité** : obligatoire même sans collecte → à héberger (page
  statique, GitHub Pages suffit) avant soumission. **À faire.**

## Restant avant soumission

1. Vérification de marque propre (INPI / EUIPO) sur « Avert » — non faite.
   Le nom *App Store* doit aussi être unique : si `Avert` est pris, replis prêts
   « Averi », « Avert — anti-hameçonnage ».
2. URL de politique de confidentialité en ligne.
3. Captures d'écran 6,9" (iPhone 17 Pro) — l'app est en FR, prévoir la série EN.
4. Notes pour la review : `review_notes.txt` (l'extension doit être activée à la
   main dans Safari, sinon le reviewer ne verra *rien* — c'est le piège n°1 de
   ce genre d'app).
