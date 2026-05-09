export type AppLocale = "zh-CN" | "en" | "ja" | "ko" | "es" | "fr" | "de";
export type LocaleTier = "core" | "experimental" | "community";

export interface LocaleInfo {
  value: AppLocale;
  label: string;
  nativeLabel: string;
  tier: LocaleTier;
}

export const PRODUCT_NAMES = {
  zh: "衔牍",
  en: "Ilios",
  ja: "理紐"
} as const;

export const TECHNICAL_PROJECT_ID = "bilin";

export const SUPPORTED_LOCALES: LocaleInfo[] = [
  { value: "zh-CN", label: "简体中文", nativeLabel: "简体中文", tier: "core" },
  { value: "en", label: "English", nativeLabel: "English", tier: "core" },
  { value: "ja", label: "日本語", nativeLabel: "日本語", tier: "experimental" },
  { value: "ko", label: "한국어", nativeLabel: "한국어", tier: "community" },
  { value: "es", label: "Español", nativeLabel: "Español", tier: "community" },
  { value: "fr", label: "Français", nativeLabel: "Français", tier: "community" },
  { value: "de", label: "Deutsch", nativeLabel: "Deutsch", tier: "community" }
];

export const TRANSLATION_TARGET_LOCALES = SUPPORTED_LOCALES;

export function productNameForLocale(locale: AppLocale): string {
  if (locale === "zh-CN") return PRODUCT_NAMES.zh;
  if (locale === "ja") return PRODUCT_NAMES.ja;
  return PRODUCT_NAMES.en;
}

export function localeInfo(locale: AppLocale): LocaleInfo {
  return SUPPORTED_LOCALES.find((item) => item.value === locale) ?? SUPPORTED_LOCALES[1];
}

export function normalizeLocale(language: string | undefined): AppLocale {
  const normalized = (language ?? "").toLowerCase();
  if (normalized.startsWith("zh")) return "zh-CN";
  if (normalized.startsWith("ja")) return "ja";
  if (normalized.startsWith("ko")) return "ko";
  if (normalized.startsWith("es")) return "es";
  if (normalized.startsWith("fr")) return "fr";
  if (normalized.startsWith("de")) return "de";
  return "en";
}
