# Registre de marques

`brands.json` est la **source unique** : le TypeScript en consomme un module
généré au build (`ts/src/generated/brands.ts`), le Swift le lit depuis le bundle
de l'extension.

Linté à chaque build (`scripts/lint-registry.ts`) : secteurs connus, domaines
bien formés et non partagés, collisions de noms et d'alias, empreintes de logo
valides. Une mauvaise entrée ici ne plante rien — elle rend juste une marque
invérifiable ou attribue un hôte à tort. D'où le linter.

## Champs

| Champ | Rôle |
|---|---|
| `brand` | Nom canonique, tel que le modèle L3 est susceptible de l'extraire |
| `aliases` | Autres noms reconnus. **Jamais 2 lettres** : « SG », « CA » déclenchaient des incohérences d'identité sur n'importe quel titre de page |
| `domains` | Domaines possédés (comparés en domaine enregistrable) |
| `auth_delegates` | Prestataires d'auth légitimes, `*.` accepté. Principal remède aux faux positifs |
| `sector`, `region` | Documentaire pour l'instant |
| `logo_hashes` | Empreintes perceptuelles du logo (optionnel) |

## Empreintes de logo

Le signal `l2.brand-logo-copy` compare les **pixels** des images de la page aux
empreintes de référence. Il couvre le cas que `l2.borrowed-brand-assets` ne voit
pas : le kit qui **recopie** le logo chez lui, où aucune heuristique d'URL ne
peut rien.

Pour ajouter une empreinte :

```bash
bun run scripts/hash-logos.ts --write "PayPal" ~/logos/paypal-*.png
```

Passer **plusieurs déclinaisons** de la même marque (clair/sombre, logotype,
monogramme, favicon) : une empreinte de 64 bits ne décrit qu'une image.

Contraintes à connaître avant de générer :

- Les deux côtés doivent produire la **même** empreinte. Ni le générateur ni le
  navigateur ne redimensionne : `sips` décode à taille naturelle, et la réduction
  en 9×8 se fait dans `grayFromRGBA`, partagé. Vérifié bit-pour-bit sur iOS 26
  (`Tests/pages/logo-hash/`). Confier la réduction au rasteriseur **ne marche
  pas** : Safari échantillonne au plus proche voisin sur une forte réduction,
  `sips` fait une moyenne d'aire — 17 bits d'écart sur le même fichier.
- Seuil de correspondance : 12 bits sur 64, mesuré (transformations bénignes du
  même logo : 4–9 bits ; marques différentes : 21–27).
- Une image quasi uniforme est refusée (`isDiscriminative`) : elle matcherait
  n'importe quel aplat.
- Seules les images **même origine** (ou `data:`) sont hachées — une image tierce
  contamine le canvas, et la re-télécharger serait un appel réseau. Un logo
  hotlinké reste couvert par `l2.borrowed-brand-assets`.

Deux empreintes de **marques différentes** à moins de 12 bits l'une de l'autre
sont indistinguables : le linter refuse ce cas. Il ne vérifiait au départ que
l'égalité exacte, ce qui laissait passer le seul cas qui compte — deux logos
*voisins*, où l'ordre du fichier décidait silencieusement du gagnant.

Une empreinte n'est pas une reproduction du logo : 64 bits, non inversibles.

## « Banque Démo » : une marque qui n'existe pas

La dernière entrée du registre est **fictive**, et c'est délibéré.

`ScoreEngine` ne lève un interstitiel que si `identityMismatch` est vrai, ce qui
exige une marque du registre. Toute page publique capable de déclencher l'alerte
forte se fait donc nécessairement passer pour une marque tout en étant hébergée
ailleurs — autrement dit, avec une vraie entreprise, c'est une page de phishing
qui fonctionne, quel que soit l'avertissement affiché dessus. Ce n'est pas une
chose à laisser sur une URL publique.

D'où une banque inventée, dont le domaine est en `.example` (réservé par la
RFC 2606, jamais enregistrable) et dont le logo est produit par le dépôt
(`design/DemoBankLogo.svg`). `docs/demo/interstitiel/` l'affiche et déclenche
exactement le même chemin de code, sans usurper personne.

Risque de faux positif en production : nul en pratique. Le domaine ne peut pas
exister, le nom n'apparaît sur aucun site réel, et l'empreinte est à plus de
12 bits de toutes les autres (le linter le vérifie). Le seul déclenchement
possible est une page affichant ce logo précis — c'est-à-dire la page de démo.
