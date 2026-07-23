# CLAUDE.md — Impostor

Extension Safari anti-phishing iOS, 100 % on-device. Spec complète : [PLAN.md](PLAN.md).
Principe : détecter **l'incohérence d'identité** (« la page ment-elle sur son identité ? »), pas la réputation.

## Architecture

- **`ts/`** — content script (TypeScript, bundlé par bun, zéro dépendance runtime).
  - `l0.ts` déclencheur point-de-capture · `l1.ts` heuristiques URL · `l2.ts` DOM · `banner.ts` UI (bandeau + interstitiel shadow-DOM) · `content.ts` orchestration · `background.ts` relais native.
  - **Source unique** du registre : `registry/brands.json` → `ts/src/generated/brands.ts` (généré au build).
- **`Shared/`** — compilé dans l'app ET l'extension : `PageDossier` (miroir de `ts/src/types.ts`), `ScoreEngine`, `BrandRegistry`, `L3Extractor`.
- **`Extension/Swift/SafariWebExtensionHandler.swift`** — reçoit le dossier, appelle moteur + L3, renvoie le verdict. **Sur iOS tout le moteur vit dans le process de l'extension**, pas l'app.
- **`App/`** — app conteneur SwiftUI : accueil, écran des limites, réglages.

## Build & test

DerivedData **hors iCloud** obligatoire (sinon codesign échoue sur les xattrs) :

```bash
./scripts/build-js.sh   # typecheck + 34 tests bun + bundle → Extension/Resources/
xcodegen generate
xcodebuild -project Impostor.xcodeproj -scheme Impostor \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/claude-501/impostor-dd build
```

Ajout/suppression de fichier source Swift → **relancer `xcodegen generate`** (erreur « cannot find X in scope » sur un fichier neuf = membership de target, pas le code).

## Contraintes environnement (Mac Intel + iCloud)

- **git** : le repo est dans iCloud → sandbox bloque les écritures `.git`. Toute commande git passe par `dangerouslyDisableSandbox`.
- **bun** : `TMPDIR`/cache redirigés dans le scratch (géré par `scripts/build-js.sh`).
- **Thermique** : MacBook Pro 16" 2019 throttle fort. Le simulateur iOS 26 lance `mediaanalysisd` (CPU 300 %+) qui **affame Safari → les content scripts ne s'injectent plus** (ressemble à « extension cassée »). Avant tout diagnostic, vérifier `pmset -g therm` et `uptime`. Un seul simulateur booté, préférer la page de test locale aux gros sites.
- **Safari démarré à froid** charge la page avant d'activer l'extension : préchauffer sur une page neutre puis naviguer.

## L3 (FoundationModels)

- `SystemLanguageModel` + guided generation (`@Generable`). Rôle **borné** : extraire l'identité revendiquée + l'intention, jamais juger. Le verdict d'identité est une comparaison factuelle registre (`BrandRegistry.identityMismatch`).
- **Indisponible sur Mac Intel et dans le simulateur** (pas d'Apple Intelligence). `availability` peut mentir `.available` puis échouer à la génération (`ModelManagerError 1026`) → kill-switch `disabledAfterFailure` pour ne pas payer ~6 s par page. Fallback L1+L2 = chemin de production.
- **Test réel : uniquement sur iPhone 17 Pro physique.**
- PCC (`PrivateCloudComputeLanguageModel`) = M7 optionnel : iOS 27 + entitlement managé Apple. Réglage prêt, non branché.

## Règles produit non négociables (cf. PLAN §5–7)

- Jamais d'alerte forte sur un signal unique (règle de convergence dans `ScoreEngine`).
- Toujours un « Continuer quand même ». Toujours expliquer le raisonnement.
- L'écran des limites (`App/LimitsView.swift`) énonce franchement ce que l'extension ne voit pas — ne jamais l'édulcorer.
- Aucun appel réseau hors PCC, même temporaire pour debug.

## État

M0→M5 faits (voir tâches / git log). Reste : **validation L3 réelle sur iPhone** (M4, présence utilisateur requise) et **M6 durcissement** (corpus de test, calibration des seuils, batterie, repasser en Swift 6 — actuellement mode 5 à cause d'un bug du checker d'isolation Xcode 26.5 sur le pattern Task+NSExtensionContext, Keychain pour l'option historique, signalement de faux positif).
