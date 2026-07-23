# Impostor — Safari anti-phishing extension (on-device)

Spec complète : `PLAN.md` (version amendée 2026-07-23, source de vérité).

## Architecture

- `project.yml` (XcodeGen) → `Impostor.xcodeproj` **généré, jamais commité**. Relancer `xcodegen generate` après tout ajout/suppression de fichier source.
- Targets : `Impostor` (app SwiftUI iOS, réglages/onboarding) + `ImpostorExtension` (Safari Web Extension). Le moteur (registre, score, FoundationModels) vit dans l'**extension** — sur iOS le native messaging aboutit dans le process appex, pas dans l'app.
- `Shared/` compilé en sources directes dans les deux targets (pas de framework). Foundation only.
- `ts/` : content script + background en TypeScript, bundlés en IIFE par `bun build` vers `Extension/Resources/*.js` (les `.js` générés sont commités pour que le build Xcode ne dépende pas de bun).

## Commandes

```sh
./scripts/build-js.sh        # typecheck (tsc) + bundle TS → Extension/Resources/
xcodegen generate            # régénère le .xcodeproj
# DerivedData OBLIGATOIREMENT hors iCloud : un -derivedDataPath dans le repo
# fait échouer codesign (« resource fork, Finder information, or similar
# detritus ») à cause des xattrs iCloud sur les produits copiés.
xcodebuild -project Impostor.xcodeproj -scheme Impostor \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/claude-501/impostor-dd build
```

## Contraintes d'environnement (durement apprises)

- **Repo dans iCloud Drive** : jamais de `node_modules` ici. `build-js.sh` copie `ts/` dans `$TMPDIR`, installe et bundle là-bas, ne rapatrie que les `.js`.
- **Sandbox Claude Code** : les écritures `.git` et les XPC CoreSimulator sont bloqués en sandbox → commandes `git`, `simctl`, `xcodebuild` (destination simulateur) passent hors sandbox.
- **Mac Intel** : Apple Intelligence indisponible (Mac ET simulateur) → L3 (`FoundationModels`) compile mais ne s'exécute que sur iPhone physique compatible (référence : iPhone 17 Pro). Le chemin de fallback L0–L2 est un chemin de production.
- Outils MCP XcodeBuildMCP : UI automation OK, mais build/install/launch timeout sur Intel → utiliser bash.

## Conventions

- Zéro appel réseau (hors PCC, M7) — pas même « temporaire pour debug ».
- Chaque niveau de cascade testable isolément sur un « dossier de page » JSON (`ts/src/types.ts` ↔ `Shared/PageDossier.swift`, à garder en miroir).
- Tests TS : `bun test` depuis la copie `$TMPDIR` (le script s'en charge).
