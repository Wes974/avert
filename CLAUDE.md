# CLAUDE.md — Avert

Extension Safari anti-phishing iOS, 100 % on-device. Spec complète : [PLAN.md](PLAN.md).
Principe : détecter **l'incohérence d'identité** (« la page ment-elle sur son identité ? »), pas la réputation.

## Architecture

- **`ts/`** — content script (TypeScript, bundlé par bun, zéro dépendance runtime).
  - `l0.ts` déclencheur point-de-capture · `l1.ts` heuristiques URL · `l2.ts` DOM · `banner.ts` UI (bandeau + interstitiel shadow-DOM) · `content.ts` orchestration · `background.ts` relais native.
  - **Source unique** du registre : `registry/brands.json` → `ts/src/generated/brands.ts` (généré au build).
- **`Shared/`** — compilé dans l'app ET l'extension : `PageDossier` (miroir de `ts/src/types.ts`), `ScoreEngine`, `BrandRegistry`, `L3Extractor`, `Localizable.xcstrings`.
- **`frames.ts` + `all_frames: true`** — le content script tourne dans chaque frame. Une sous-frame ne fait que L0 et **rapporte** ses points de capture à la frame du haut *via le background* (`tabs.sendMessage`, frameId 0) : jamais `postMessage`, qu'une page pourrait écouter pour détecter Avert. Seule la frame du haut décide et affiche.
- **`Extension/Swift/SafariWebExtensionHandler.swift`** — reçoit le dossier, appelle moteur + L3, renvoie le verdict. **Sur iOS tout le moteur vit dans le process de l'extension**, pas l'app.
- **`App/`** — app conteneur SwiftUI : accueil, écran des limites, réglages.

## Build & test

DerivedData **hors iCloud** obligatoire (sinon codesign échoue sur les xattrs) :

```bash
./scripts/build-js.sh   # typecheck + 34 tests bun + bundle → Extension/Resources/
xcodegen generate
xcodebuild -project Avert.xcodeproj -scheme Avert \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/claude-501/impostor-dd build
```

## « Vérifier ce lien » (hors navigateur)

- **Deux implémentations de L1** : `ts/src/l1.ts` (extension) et `Shared/URLHeuristics.swift` (App Intent + extension de partage). Obligatoire : aucun JS hors du navigateur, et Safari n'atteint une page qu'une fois ouverte — donc tout le smishing était invisible.
- **La duplication est verrouillée** par `Tests/corpus/l1.json`, lu par les DEUX suites. Toute divergence non déclarée casse le build. Les divergences réelles sont documentées dans le corpus. Vérifié en cassant volontairement une attente (les 20 cas s'exécutent, la sentinelle est vue).
- Parseur d'URL **écrit à la main** : `URLComponents` mange les hôtes non ASCII (là où vivent les homographes), et le piège du userinfo (`paypal.com@evil.top`) doit résoudre vers `evil.top`. Un hôte sans point ou avec des espaces est refusé — sinon du texte quelconque recevait un verdict *rassurant*.
- Le verdict d'un lien nu (`LinkCheck`) est un **type à part**, pas `ScoreEngine` avec un dossier factice : dix fois moins d'indices. Trois niveaux ; un seul indice de distance d'édition n'accuse jamais. La mise en garde « je n'ai lu que l'adresse, pas la page » accompagne **tous** les verdicts.
- `Shared/UI/` est exclu de l'extension Safari : ce process tourne sur chaque page et ne dessine rien.
- **Pièges XcodeGen** : `info.path` fait *générer* le plist (un `NSExtension` écrit à la main y est écrasé — le déclarer dans `info.properties`) ; sans `- sdk: AppIntents.framework` l'intent compile mais n'apparaît jamais dans Siri/Raccourcis (`appintentsmetadataprocessor` dit « No AppIntents.framework dependency found »).

## Empreinte perceptuelle des logos

- `dhash.ts` (pur, testable) + `logo.ts` (glu DOM) + `scripts/hash-logos.ts` (générateur, `sips` comme décodeur). Signal `l2.brand-logo-copy`, poids 25, **signal d'identité** (multiplicateur ×2).
- **Piège majeur** : ne jamais laisser le rasteriseur réduire l'image. Sur iOS 26, `drawImage` vers un canvas 9×8 **échantillonne au plus proche voisin** (grille = couleurs source exactes) alors que `sips` fait une moyenne d'aire → 17 bits d'écart sur le même fichier, et empreinte instable au moindre redimensionnement. Solution : blit 1:1 puis moyenne d'aire dans `grayFromRGBA`, **partagé** par le générateur et le navigateur → empreintes bit-pour-bit identiques (vérifié, `Tests/pages/logo-hash/`).
- Seuil 12/64 bits, mesuré (transformations bénignes 4–9, marques différentes 21–27). Images quasi uniformes refusées (`isDiscriminative`) : elles matcheraient n'importe quel aplat.
- Seules les images **même origine** ou `data:` sont hachées (canvas contaminé sinon, et re-télécharger = appel réseau interdit). Le logo hotlinké reste couvert par `l2.borrowed-brand-assets`.
- Table de référence **vide** pour l'instant → signal inerte (défaut voulu). Remplir avec `bun run scripts/hash-logos.ts --write <marque> <images…>`, cf. `registry/README.md`.

## Site public et pages de démonstration (`docs/`)

Servi par GitHub Pages depuis `docs/` sur `main` → **https://wes974.github.io/avert/**.
Contient la landing, la politique de confidentialité (FR + EN, exigée par l'App
Store) et deux pages piégées pour qu'un testeur puisse vérifier l'extension sans
avoir à croiser du vrai phishing.

- `docs/demo/alerte/` → **bandeau** : `cross-origin-form` (25) + `hidden-capture-field` (30) = 55. Aucune marque, donc pas de ×2 : l'interstitiel est hors d'atteinte par construction.
- `docs/demo/interstitiel/` → **écran plein** : + `brand-logo-copy` (25) → 80 ×2 = 160.

**Pourquoi une marque inventée.** Un interstitiel exige `identityMismatch`, donc
une marque du registre. Une page publique qui déclenche l'alerte forte se fait
donc forcément passer pour une marque depuis un hôte qu'elle ne possède pas —
avec une vraie entreprise, c'est une page de phishing fonctionnelle, quel que
soit l'avertissement affiché, sur une URL au nom de l'auteur. D'où « Banque
Démo » (`registry/README.md`).

**Dégradation volontaire** : sans reconnaissance du logo, la page 2 retombe sur
un bandeau. Un testeur qui rapporte « bandeau au lieu d'écran plein » nous dit
que l'empreinte n'a pas matché — pas que l'extension est morte. C'est le seul
diagnostic disponible à distance.

Pièges :

- Le logo est rendu **sans coins arrondis** (`design/DemoBankLogo.svg`) : un
  arrondi dans le PNG = pixels semi-transparents, et `sips` et le canvas de
  Safari compositent l'alpha chacun de leur côté. L'arrondi est en CSS.
- `ts/tests/demo-pages.test.ts` analyse les fichiers **réellement publiés** :
  il n'injecte que le `<body>`, sinon happy-dom résout le `<link rel=stylesheet>`
  et émet une requête réseau depuis la suite de tests de l'app qui promet de ne
  jamais en faire.
- `build-js.sh` recopie `docs/demo/` à côté du scratch, comme `Tests/corpus/`,
  sinon le test ne trouve pas les pages.
- Toute modification du registre **exige un nouveau build TestFlight** : il est
  embarqué dans le bundle, pas téléchargé.

## Localisation

- Langue source **fr** (`options.developmentLanguage`), EN traduit. Un seul catalogue `Shared/Localizable.xcstrings` compilé dans les **deux** bundles (l'app pour son UI, l'extension parce que le texte du verdict est produit par `ScoreEngine`).
- **Piège** : une chaîne stockée dans un tableau de données doit être `LocalizedStringKey`, pas `String`, sinon elle **sort silencieusement du catalogue** (`xcodebuild -exportLocalizations` n'extrayait que 14 chaînes sur ~50).
- `xcodebuild -exportLocalizations` **réécrit le .xcstrings** (normalisation + marqueurs `stale` + entrée `"%@"`), à nettoyer après usage.
- Vérification qui compte : `xcrun simctl launch <SIM> com.ouweis.avert -AppleLanguages "(en)"` puis capture d'écran. Le contenu du `.strings` compilé ne prouve pas que la clé générée à l'exécution correspond.
- Côté extension : `_locales/{fr,en}/messages.json` + `default_locale`, lus par `browser.i18n` (`ts/src/i18n.ts`, avec repli FR si l'API manque). `_locales` est ajouté en **folder reference** dans `project.yml` (sinon XcodeGen aplatit l'arborescence et les deux `messages.json` collisionnent).

Ajout/suppression de fichier source Swift → **relancer `xcodegen generate`** (erreur « cannot find X in scope » sur un fichier neuf = membership de target, pas le code).

### Règle XcodeGen : tout `path:` est une SORTIE, jamais une source

Piège rencontré **trois fois** (Info.plist de l'extension Safari, Info.plist de l'extension d'action, entitlements de l'app). Dès qu'un bloc `info:` ou `entitlements:` déclare un `path:`, XcodeGen **génère** ce fichier et écrase silencieusement ce qui s'y trouve. Un `NSExtension` ou un entitlement écrit à la main y disparaît sans avertissement, et le symptôme apparaît plus tard : extension absente de la feuille de partage, capacité manquante à la signature.

→ Le contenu va dans `properties:` sous le bloc, dans `project.yml`. Le fichier sur disque est un artefact, pas une source. Ne jamais l'éditer.

### Provisionnement sans Xcode

Contrairement à ce que je croyais, **aucune capacité ne nécessite l'interface d'Xcode**. Chaîne complète en ligne de commande :

1. `asc bundle-ids capabilities add --bundle <ID> --capability ICLOUD --settings '[{"key":"ICLOUD_VERSION","options":[{"key":"XCODE_6","enabled":true}]}]'` (sans `--settings`, l'API répond « CloudkitVersion null »)
2. Entitlements déclarés dans `project.yml`
3. `xcodebuild -allowProvisioningUpdates` — **crée les identifiants manquants**, y compris les conteneurs iCloud, via le service qu'utilise Xcode (que l'API App Store Connect n'expose pas)

Vérifier le résultat sur le profil embarqué, pas sur le fichier généré :
`security cms -D -i <App>.app/embedded.mobileprovision | plutil -extract Entitlements xml1 -o - -`

## Contraintes environnement (Mac Intel + iCloud)

- **git** : le repo est dans iCloud → sandbox bloque les écritures `.git`. Toute commande git passe par `dangerouslyDisableSandbox`.
- **bun** : `TMPDIR`/cache redirigés dans le scratch (géré par `scripts/build-js.sh`).
- **La plateforme iOS disparaît aux mises à jour de Xcode.** Symptômes simultanés : `xcrun simctl list devices available` ne montre que « Unavailable », et `xcodebuild archive -destination 'generic/platform=iOS'` échoue avec « iOS 26.5 is not installed ». Trompeur, parce que `xcodebuild -showsdks` **liste toujours** le SDK iOS 26.5 : le SDK et le composant plateforme sont deux choses distinctes depuis Xcode 16. Correctif : `xcodebuild -downloadPlatform iOS` (~10 Go). Rien à voir avec le projet, ni avec la sandbox — ne pas partir en débogage de signature.
- **Thermique** : MacBook Pro 16" 2019 throttle fort. Le simulateur iOS 26 lance `mediaanalysisd` (CPU 300 %+) qui **affame Safari → les content scripts ne s'injectent plus** (ressemble à « extension cassée »). Avant tout diagnostic, vérifier `pmset -g therm` et `uptime`. Un seul simulateur booté, préférer la page de test locale aux gros sites.
- **Safari démarré à froid** charge la page avant d'activer l'extension : préchauffer sur une page neutre puis naviguer.
- **Content script périmé après réinstallation** : un onglet déjà ouvert continue d'exécuter l'ANCIEN bundle. Symptôme trompeur — un verdict correct mais issu d'un code d'une version antérieure, donc sans les signaux récents. Repère fiable : la ligne de debug (`pass=`, absent avant la couverture SPA) et l'hôte affiché (`host:port` avant le refinement, `hostname` seul après). **Après chaque install : quitter Safari depuis le sélecteur d'apps**, pas seulement fermer l'onglet.
- **Vérifier ce qu'on installe, pas ce qu'on a construit** : `grep logo_hashes <App>.app/PlugIns/*.appex/brands.json` avant `devicectl install`. Un build device antérieur à une modif du registre donne un signal muet qu'on prend pour un bug.

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

M0→M5 faits, **M4 validé sur iPhone 17 Pro réel** (L3 extrait brand=PayPal, mismatch=true), **M6 fait à ~90 %** :
- ✅ Corpus négatif zéro alerte forte (bug auth_delegate cross-origin corrigé), debug derrière `#if DEBUG`, latence instrumentée, LoginHistoryStore Keychain + signal historique, robustesse L3 (indices d'identité only, en-têtes en dernier recours).
- ⏳ **Reste (nécessite l'utilisateur / son matériel)** :
  - **Mesure batterie/thermique** sur session iPhone réelle (Instruments Energy Log) — profiling utile = latence (fait) + énergie (à mesurer).
  - **App group** `group.com.ouweis.impostor` (entitlement + assignation via Xcode GUI une fois, cf. skill xcodegen note #8) pour que le toggle historique et la purge soient partagés app↔extension. Sans ça, le signal historique reste inactif (défaut voulu).
  - **Swift 6** : bloqué par un bug du region-isolation checker Xcode 26.5 (capture `NSExtensionContext` dans `Task`) — reproduit avec Task/Task.detached/refacto. Rester en mode langage 5, retenter aux MAJ Xcode.
  - Signalement de faux positif (log local exportable).
