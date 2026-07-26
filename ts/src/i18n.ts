// Localised strings for the injected UI.
//
// Source of truth is `Extension/Resources/_locales/<lang>/messages.json`, read
// through `browser.i18n` (Safari picks the locale from the system). The French
// defaults are kept here as a fallback: `getMessage` returns "" for an unknown
// key or when the API is unavailable, and an alert with an empty label would be
// worse than an alert in the wrong language.

const FALLBACK_FR: Record<string, string> = {
  fallbackReason:
    "Cette page présente plusieurs caractéristiques de page de phishing. Vérifiez l'adresse avant de saisir quoi que ce soit.",
  dismiss: "Ignorer",
  dismissAria: "Ignorer l’avertissement",
  interstitialTitle: "Attention — page suspecte",
  leavePage: "Quitter cette page",
  proceed: "Continuer quand même",
  proceedAria: "Continuer quand même — maintenir appuyé",
  longPressHint: "Maintenez appuyé pour continuer",
  confirmProceed: "Continuer vers cette page malgré l’avertissement ?",
  askForHelp: "Demander à un proche",
  askForHelpAria: "Demander à un proche si ce site est fiable",
  askSent: "Demande envoyée",
  askWhatIsShared: "Votre proche verra uniquement l’adresse :",
};

export function t(key: keyof typeof FALLBACK_FR): string {
  try {
    const value = browser.i18n?.getMessage(key);
    if (value) return value;
  } catch {
    // No i18n API (unit tests, unexpected host) — fall through.
  }
  return FALLBACK_FR[key] ?? "";
}
