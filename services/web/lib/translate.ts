import {
  formatMessage,
  type Locale,
  type MessageKey,
  type Messages,
  type Translate,
  type TranslationVariables,
} from "./i18n.ts";
import ar from "./messages/ar.ts";
import en from "./messages/en.ts";
import ru from "./messages/ru.ts";
import tr from "./messages/tr.ts";

// Every locale at once, for server code: pages, metadata and components that render
// only on the server. A client component imports none of this and translates
// through useI18n(), which downloads the page's locale alone.
const MESSAGES: Record<Locale, Messages> = { ru, en, ar, tr };

export function translate(
  locale: Locale,
  key: MessageKey,
  variables: TranslationVariables = {},
): string {
  return formatMessage(MESSAGES[locale][key], variables);
}

export function translatorFor(locale: Locale): Translate {
  return (key, variables) => translate(locale, key, variables);
}
