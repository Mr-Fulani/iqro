/** What an ayah or a du'a shares besides its title, as the app's ContentShare. */
export type ContentShareText = {
  arabic: string;
  translation: string;
  /** A practical line, such as how many times a du'a is said. Only the message has it, as in the app. */
  note?: string;
  /** Where it comes from: the translator or the du'a's sources. */
  reference: string;
};

/**
 * The message of the app (contentShareText): the title, the Arabic, the
 * meaning in quotes, the note, the source and the link.
 */
export function contentShareText(
  title: string,
  { arabic, translation, note = "", reference }: ContentShareText,
  readInIqro: string,
  url: string,
): string {
  return [
    title,
    arabic.trim(),
    translation.trim() && `«${translation.trim()}»`,
    note.trim(),
    reference.trim(),
    `${readInIqro}: ${url}`,
  ].filter(Boolean).join("\n\n");
}

/**
 * Sends the message without its picture, for when the share dialog cannot
 * load: Web Share where the browser has it, the clipboard elsewhere.
 */
export async function shareTextOnly(
  title: string,
  text: string,
): Promise<"shared" | "copied" | "cancelled" | "failed"> {
  try {
    if (typeof navigator.share === "function") {
      await navigator.share({ title, text });
      return "shared";
    }
    await navigator.clipboard.writeText(text);
    return "copied";
  } catch (error) {
    return error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
  }
}
