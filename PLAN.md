# Avert — Extension Safari anti-phishing, on-device

> Spec de travail. Version amendée le 2026-07-23 (session de cadrage) — les amendements par rapport au plan initial sont marqués **[amendé]**.

---

## 1. Objectif

Une extension Safari (iOS d'abord, macOS ensuite **[amendé]**) qui analyse chaque page à la volée et n'intervient que lorsqu'elle détecte une incohérence d'identité — typiquement une page qui se fait passer pour une marque sans en être le domaine légitime.

**Principe directeur** : on abandonne la question *« ce site est-il connu comme malveillant ? »* (perdue d'avance face au phishing zero-day) pour *« ce site ment-il sur son identité ? »* (calculable instantanément, sans base externe).

### Contraintes

| Contrainte | Détail |
|---|---|
| Zéro exfiltration **[amendé]** | Aucune donnée de page ne quitte l'écosystème privé de l'utilisateur. Pas de télémétrie, pas de serveur à nous. Private Cloud Compute (garanties Apple) est acceptable en escalade — voir L3. |
| Silence par défaut | Pas de badge, pas de notification, pas d'UI sur une page normale. |
| Pas d'historique par défaut | La mémorisation des domaines de connexion est une **option désactivée**, jamais le cœur du système. |
| Coût maîtrisé | Le modèle ne se réveille que sur un très petit sous-ensemble de pages. |
| Honnêteté d'interface | Ne jamais laisser croire à une couverture totale. |

---

## 2. Architecture générale

```
┌─────────────────────────────────────────────────┐
│  Safari Web Extension (TS compilé — content     │
│  script + background)                           │
│  L0 déclencheur · L1 URL · L2 DOM               │
│  → extrait un "dossier de page" compact         │
└────────────────────┬────────────────────────────┘
                     │ native messaging (via background)
┌────────────────────▼────────────────────────────┐
│  SafariWebExtensionHandler (process extension)  │
│  · Brand registry embarqué                      │
│  · Moteur de score                              │
│  · L3 : Foundation Models (on-device)           │
└─────────────────────────────────────────────────┘
```

**[amendé]** Sur iOS le native messaging aboutit dans le **process de l'extension** (`SafariWebExtensionHandler`), pas dans l'app conteneur : registre, moteur de score et appel modèle vivent donc dans la target extension (code partagé `Shared/` compilé dans les deux targets). L'app conteneur SwiftUI porte les réglages, l'onboarding et l'écran des limites.

**Stack** : projet généré par **XcodeGen** (`project.yml` commité, pas de `.xcodeproj`). App conteneur SwiftUI + Safari Web Extension. **TypeScript** (bundlé par bun, zéro dépendance runtime) pour les scripts, Swift pour le moteur et l'appel modèle. `FoundationModels` pour L3, avec dégradation propre si indisponible.

**[amendé]** Environnement de dev : Mac Intel → compilation OK (Xcode 26, binaire Universal) mais **ni Apple Intelligence ni simulateur avec modèle** ; L3 n'est testable que sur iPhone physique compatible (iPhone 17 Pro de référence). La version macOS tournera en L0–L2 sur Mac Intel — le fallback est un chemin de production, pas un cas d'erreur.

---

## 3. La cascade de détection

L'ordre compte : du quasi-gratuit au coûteux. **~95 % des pages doivent s'arrêter à L0.**

### L0 — Déclencheur (coût ≈ 0)

On n'analyse que les pages présentant un **point de capture** :

- champ `input[type=password]`
- formulaire de paiement (numéro de carte, CVV, champs `autocomplete="cc-*"`)
- saisie de code 2FA / OTP
- champ de phrase de récupération (seed phrase, crypto)
- upload de pièce d'identité

Pas de point de capture → **on ne fait rien**. Fin de l'histoire.

### L1 — Analyse de l'URL (< 1 ms, pur TS)

Signaux calculés localement, sans réseau :

- **Homographes / IDN** : mélange de scripts Unicode dans le domaine (cyrillique + latin), punycode déguisé.
- **Typosquatting** : distance de Levenshtein ≤ 2 contre le registre de marques, substitutions clavier, caractères doublés/omis.
- **Combosquatting** : `apple-verification-secure.com`, marque + mot-clé de sécurité.
- **Structure anormale** : sous-domaines excessifs, marque placée en sous-domaine d'un domaine tiers (`paypal.com.session-verify.xyz`), IP littérale, port exotique.
- **TLD à faible réputation** (pondération faible — jamais utilisé seul).

**[amendé — retirés]** : âge du certificat, anomalie TLS, âge du domaine. Aucune API d'extension Safari n'expose le certificat, et whois = réseau. Remplacé, si l'option historique opt-in est active, par « domaine de connexion jamais vu localement ».

### L2 — Structure et comportement de la page (quelques ms)

- **Formulaire cross-origin** : `action` pointant vers un domaine différent de celui affiché. Signal très fort.
- **Champs masqués** : password en `opacity:0`, hors viewport, dans une iframe cachée, ou saisie reconstruite en `<canvas>` / overlay d'image. → **La ruse devient l'indice.**
- **Anti-inspection** : blocage du clic droit, de la sélection, obfuscation lourde du JS.
- **Iframe imbriquée** hébergeant le formulaire depuis un domaine tiers non déclaré.
- **Chaîne de redirection** ayant mené à la page (dans la limite de ce que `webNavigation` expose sur Safari).
- **Ressources visuelles empruntées** : favicon / logo chargés depuis le CDN de la marque alors que le domaine ne correspond pas.

### L3 — Modèle (seulement si L1+L2 dépassent un seuil bas)

Rôle unique et borné : **extraire l'identité revendiquée** par la page, pas juger de la malveillance.

Sortie structurée (guided generation `@Generable`) :

```json
{
  "claimed_brand": "La Banque Postale",
  "confidence": 0.87,
  "page_intent": "login | payment | 2fa | recovery | other",
  "urgency_markers": ["compte suspendu", "action sous 24h"],
  "generic_scam_patterns": ["menace de fermeture", "délai artificiel"]
}
```

1. L'extraction est ce qu'un modèle 3B fait **bien**.
2. Le modèle n'a **aucune** connaissance à jour du monde réel — excellent détecteur d'**intention**, mauvais détecteur d'**identité**. Le verdict d'identité est rendu par comparaison factuelle locale : `claimed_brand → domaine(s) attendu(s)` vs `domaine réel`.

**[amendé] L3 à deux étages** :
- **Étage 1 (défaut)** : `SystemLanguageModel` on-device (iOS 26+, aucun entitlement).
- **Étage 2 (M7, optionnel)** : escalade `PrivateCloudComputeLanguageModel` quand la confiance on-device est basse alors que L1+L2 sont élevés. Conditionné à iOS 27 + entitlement managé `com.apple.developer.private-cloud-compute` (à demander à Apple, non garanti). Désactivable dans les réglages. Jamais requis pour un verdict.

> `generic_scam_patterns` est la porte de sortie pour les marques **absentes** du registre.

---

## 4. Le registre de marques

Fichier embarqué, versionné dans le repo, mis à jour à chaque release (**pas de fetch au runtime**).

```json
{
  "brand": "La Banque Postale",
  "aliases": ["Banque Postale", "LBP"],
  "domains": ["labanquepostale.fr"],
  "auth_delegates": ["*.wl-fr.com"],
  "sector": "banking",
  "region": ["FR"]
}
```

- Cible : 300–800 entrées (banques FR/EU, Apple, Google, Microsoft, opérateurs, impôts/administrations, transporteurs, plateformes crypto, réseaux sociaux). Démarrage : ~100.
- `auth_delegates` couvre les prestataires d'authentification légitimes — principal remède aux faux positifs.
- Le registre **confirme** une identité connue ; il ne conditionne pas toute la détection.

---

## 5. Moteur de score et seuils

Jamais de tout-ou-rien. Score cumulatif avec **multiplicateur d'identité** :

| Signal | Poids indicatif |
|---|---|
| Formulaire cross-origin | +25 |
| Champ de saisie dissimulé | +30 |
| Homographe / punycode | +35 |
| Typosquat d'une marque du registre | +30 |
| Anti-inspection | +10 |
| Domaine de connexion jamais vu (opt-in historique) | +10 |
| **Marque revendiquée ≠ domaine (et pas un `auth_delegate`)** | **×2 sur le total** |

**Seuils** :
- `< 40` → silence total
- `40–70` → bandeau discret, non bloquant, dismissible
- `> 70` **et** incohérence d'identité confirmée → interstitiel plein écran avant toute saisie

Règle d'or : **jamais d'alerte forte sur un signal unique.** Il faut convergence.

---

## 6. UI et ton des alertes

> ⚠️ **Cette page se présente comme La Banque Postale**, mais elle est hébergée sur `lbp-secure-verif.top`, qui n'est pas un domaine de cette banque.
>
> Ne saisissez pas vos identifiants. Si vous pensez que c'est une erreur, [signaler un faux positif].

- Toujours **expliquer le raisonnement**.
- Toujours un chemin de sortie (« continuer quand même »).
- Signalement de faux positif **local** (log dans l'app, exportable manuellement). Pas de télémétrie.
- Écran « Ce que cette extension ne voit pas » dans les réglages.

---

## 7. Confidentialité et permissions

- Zéro requête réseau à nous. À vérifier en CI (absence de symboles réseau côté Swift, pas de `fetch`/`XMLHttpRequest` côté JS hors PCC).
- Contenu de page envoyé au modèle **éphémère**, jamais persisté.
- Option désactivée par défaut : « mémoriser les domaines où je me connecte » → Keychain, purgeable, jamais synchronisé.
- **[amendé] Permissions** : `<all_urls>` assumé dans le manifest — la détection automatique d'un point de capture l'exige (`activeTab` est structurellement incompatible avec L0). Le modèle de permission par site de Safari (l'utilisateur accorde site par site ou globalement) reste la vraie barrière ; l'honnêteté passe par l'explication dans l'app, pas par un manifest minimaliste d'apparence.

---

## 8. Faiblesses connues (à documenter dans le README)

1. **Adaptation adverse** — l'attaquant itère plus vite que nous.
2. **Faux positifs sur délégations d'auth légitimes** — mitigé par `auth_delegates`, jamais à zéro.
3. **Batterie / thermique sur iPhone** — mitigé par la cascade ; à mesurer.
4. **Couverture limitée au registre** — marque absente = pas de verdict d'identité (seulement schéma générique). **Ne jamais le masquer.**
5. **L'extension est elle-même une cible** — elle lit les pages sensibles.
6. **Faux sentiment de sécurité** — raison d'être de l'écran « ce que je ne vois pas ».
7. **[amendé] Limite mémoire du process extension iOS** — l'appel FoundationModels part du process appex (limites strictes). Le modèle tourne côté système via XPC donc a priori OK, mais **à prouver sur appareil avant d'investir M4** (risque n°1).

---

## 9. Jalons

- **M0 — Squelette** : XcodeGen, app + extension iOS, toolchain TS, **native messaging aller-retour validé en simulateur**.
- **M1 — L0 + L1** : déclencheur, heuristiques URL, tests unitaires, log local, aucune alerte.
- **M2 — L2** : analyse DOM, score cumulatif, premier bandeau.
- **M3 — Registre** : ~100 marques FR/EU, comparaison d'identité, `auth_delegates`.
- **M4 — L3 on-device** : `SystemLanguageModel` + `@Generable`, fallback propre. **Validation mémoire/latence sur iPhone 17 Pro en préalable.**
- **M5 — UI** : interstitiel, faux positifs, écran des limites, option historique.
- **M6 — Durcissement** : corpus de test, calibration, batterie, audit surface d'attaque.
- **M7 — PCC (optionnel)** : escalade `PrivateCloudComputeLanguageModel` si entitlement obtenu + iOS 27 stable.

---

## 10. Stratégie de test

- **Corpus positif** : kits de phishing archivés (PhishTank / OpenPhish, en local) rejoués depuis un serveur statique local.
- **Corpus négatif — le plus important** : top sites FR avec login réels (SSO, 3-D Secure, prestataires bancaires). **Objectif : zéro alerte forte.**
- **Cas adverses forgés** : canvas, hors viewport, iframe, homographe, redirections.
- **Métriques** : faux positifs (priorité absolue), détection zero-day simulé, latence P95 par niveau, batterie.

---

## Notes d'implémentation

- Chaque niveau de la cascade est **testable isolément**, entrée « dossier de page » JSON.
- Le parsing côté Swift est défensif ; la sortie L3 passe par guided generation (pas de JSON à parser).
- Ne jamais introduire d'appel réseau vers autre chose que PCC, même « temporaire pour debug ».
