# Avert

Extension Safari iOS qui prévient quand une page **ment sur son identité**.
Tout se passe sur l'appareil : aucune liste noire, aucun appel réseau, aucun compte.

La question n'est pas « ce site est-il signalé quelque part ? » mais « cette page
revendique-t-elle une marque qui ne correspond pas au domaine qui l'héberge ? ».
Une liste noire arrive toujours après ; une incohérence d'identité est visible
immédiatement, y compris sur un domaine créé il y a une heure.

## Comment ça décide

Une cascade, du gratuit au coûteux — 4 étages, et la grande majorité des pages
s'arrêtent au premier :

| Étage | Rôle | Coût |
|---|---|---|
| **L0** | Y a-t-il un point de capture ? (mot de passe, carte, OTP, phrase de récupération) Sinon : **rien du tout**. | ~0 |
| **L1** | L'adresse : homographes, punycode, typosquat, marque greffée en sous-domaine, structure. | µs |
| **L2** | La page : champ caché, formulaire cross-origin, iframe tierce qui collecte, logo emprunté. | ms |
| **L3** | Modèle de langage **on-device** (FoundationModels) : extraire la marque revendiquée. | ~2 s |

Le modèle **n'a pas le droit de juger**. Il extrait une identité revendiquée ;
c'est du Swift déterministe qui la compare au registre de marques
(`registry/brands.json`) et qui décide. Cette séparation est ce qui rend le
verdict explicable et testable — et elle évite de demander à un LLM « est-ce du
phishing ? », question à laquelle il répond volontiers et mal.

Le score exige une **convergence** : un signal unique n'alerte jamais, quel que
soit son poids. Une alerte forte exige en plus une incohérence d'identité
confirmée. Il y a toujours un « continuer quand même ».

## Règles non négociables

- **Silence par défaut** — rien ne s'affiche sur une page normale. Pas de badge,
  pas de score, pas de « site sûr » : un outil qui parle tout le temps n'est plus
  écouté quand il compte.
- **Zéro exfiltration** — aucune donnée de page ne quitte l'appareil. Seul le
  *nom d'hôte* passe du content script au natif, jamais l'URL complète (le chemin
  ou la query d'une page sensible contient parfois le secret lui-même).
  `scripts/check-no-network.sh` échoue si un bundle contient la moindre API réseau.
- **Honnêteté d'interface** — l'app consacre un écran entier à ce qu'elle ne sait
  pas faire. Le pire échec de cet outil n'est pas de rater un site : c'est de
  faire croire qu'on est couvert.

## Architecture

```
ts/            content script (TypeScript, zéro dépendance runtime)
  l0 l1 l2     déclencheur · URL · DOM
  frames       couverture multi-frames (une sous-frame rapporte, le top décide)
  banner       bandeau + interstitiel en shadow DOM closed
Shared/        compilé dans l'app ET l'extension : PageDossier, ScoreEngine,
               BrandRegistry, L3Extractor
Extension/     SafariWebExtensionHandler — sur iOS, tout le moteur vit ici
App/           app conteneur SwiftUI : accueil, limites, réglages
registry/      brands.json — source unique, lintée en CI
store/         métadonnées App Store
Tests/         tests Swift (Swift Testing) + pages de test manuelles
```

## Build

```bash
./scripts/build-js.sh   # lint registre + typecheck + tests + bundle + garde réseau
xcodegen generate
xcodebuild -project Avert.xcodeproj -scheme Avert \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/avert-dd build
```

`.xcodeproj` n'est pas versionné (XcodeGen, `project.yml`). DerivedData doit
rester **hors iCloud**, sinon codesign échoue sur les xattrs.

## État

Cascade L0→L3 validée sur iPhone 17 Pro réel (extraction d'identité correcte,
~2,3 s). 53 tests TypeScript + 15 tests Swift. Reste avant soumission : mode
famille, localisation, empreinte de logo, vérification device de la couverture
multi-frames, URL de politique de confidentialité.

L3 **ne fonctionne que sur un appareil Apple Intelligence** : pas de Mac Intel,
pas de simulateur. Le chemin L1+L2 est le chemin de production partout ailleurs.

## Antériorité

Le concept n'est pas une invention : la détection de phishing par incohérence de
marque est l'état de l'art académique (PhishLLM, KnowPhish — USENIX 2024), et il
existe au moins une app App Store au pitch voisin (PhishGuard). La différence
revendiquée ici est d'exécution : 100 % on-device et vérifiable, LLM cantonné à
l'extraction, verdict déterministe, honnêteté d'interface, gratuit et sans compte.
