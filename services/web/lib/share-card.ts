// The share picture of the app's ShareCard (core/share/content_share.dart),
// drawn on a canvas: the brand's green with a gold frame, the seal, the title,
// the Arabic, the meaning, its source and the site. Sizes are the app's logical
// pixels; the PNG is twice as dense, as in the app.

export type ShareCardContent = {
  /** «Аль-Бакара · 2:255», or the du'a's chapter and number. */
  title: string;
  arabic: string;
  translation: string;
  /** The translator, shown under the meaning. */
  reference: string;
};

export type ShareCardFonts = {
  /** CSS font-family lists, as the reader's computed styles give them. */
  arabic: string;
  text: string;
};

const WIDTH = 540;
const HEIGHT = 675;
const PIXEL_RATIO = 2;
const GOLD = "#e2b665";
const IVORY = "#f4edda";
const SITE = "iqro.forum";

// Long passages get a smaller script so the whole text fits the card.
function arabicSize(text: string): number {
  if (text.length < 90) return 34;
  if (text.length < 200) return 28;
  if (text.length < 360) return 23;
  if (text.length < 600) return 19;
  return 16;
}

function isRtl(text: string): boolean {
  return /[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff]/.test(text.match(/\p{L}/u)?.[0] ?? "");
}

// Greedy word wrap; the last allowed line ends with an ellipsis when text is left.
function wrap(
  context: Pick<CanvasRenderingContext2D, "measureText">,
  text: string,
  width: number,
  maxLines: number,
): string[] {
  const lines: string[] = [];
  let line = "";
  for (const word of text.trim().split(/\s+/).filter(Boolean)) {
    const candidate = line ? `${line} ${word}` : word;
    if (!line || context.measureText(candidate).width <= width) {
      line = candidate;
      continue;
    }
    if (lines.length === maxLines - 1) {
      while (line.includes(" ") && context.measureText(`${line}…`).width > width) {
        line = line.slice(0, line.lastIndexOf(" "));
      }
      return [...lines, `${line}…`];
    }
    lines.push(line);
    line = word;
  }
  if (line) lines.push(line);
  return lines;
}

/**
 * The title ends with its reference after the last « · »: «Аль-Бакара · 2:255»,
 * «… · #69». A title too long for its lines loses words of the name, never the
 * reference.
 */
export function titleLines(
  context: Pick<CanvasRenderingContext2D, "measureText">,
  title: string,
  width: number,
  maxLines: number,
): string[] {
  const lines = wrap(context, title, width, Infinity);
  if (lines.length <= maxLines) return lines;
  const cut = title.lastIndexOf(" · ");
  const words = cut < 0 ? [] : title.slice(0, cut).trim().split(/\s+/);
  for (let count = words.length - 1; count > 0; count -= 1) {
    const shortened = wrap(context, `${words.slice(0, count).join(" ")}…${title.slice(cut)}`, width, Infinity);
    if (shortened.length <= maxLines) return shortened;
  }
  return wrap(context, title, width, maxLines);
}

function roundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
) {
  context.beginPath();
  context.moveTo(x + radius, y);
  context.arcTo(x + width, y, x + width, y + height, radius);
  context.arcTo(x + width, y + height, x, y + height, radius);
  context.arcTo(x, y + height, x, y, radius);
  context.arcTo(x, y, x + width, y, radius);
  context.closePath();
}

type Block = { lines: string[]; font: string; lineHeight: number; rtl: boolean };

function block(
  context: CanvasRenderingContext2D,
  text: string,
  font: string,
  lineHeight: number,
  width: number,
  maxLines: number,
): Block {
  context.font = font;
  return { lines: text.trim() ? wrap(context, text, width, maxLines) : [], font, lineHeight, rtl: isRtl(text) };
}

function drawBlock(
  context: CanvasRenderingContext2D,
  { lines, font, lineHeight, rtl }: Block,
  x: number,
  top: number,
  align: CanvasTextAlign,
) {
  context.font = font;
  context.direction = rtl ? "rtl" : "ltr";
  context.textAlign = align;
  lines.forEach((line, index) => context.fillText(line, x, top + lineHeight * (index + 0.5)));
}

// How long the first picture waits for its fonts and the seal; whatever comes
// later is drawn into a second picture.
const ASSET_WAIT_MS = 4000;

function loadImage(url: string): Promise<HTMLImageElement | null> {
  const image = new Image();
  image.src = url;
  return image.decode().then(() => image, () => null);
}

// Fetches the faces, and only the unicode ranges, the card draws. next/font
// follows each web font with a local() metric fallback, such as Times New
// Roman after Amiri; where that system font is missing, as on Linux, loading
// the whole list rejects. So each family loads on its own and may fail.
function loadFonts(requests: [style: string, families: string, text: string][]): Promise<unknown> {
  return Promise.allSettled(requests.flatMap(([style, families, text]) =>
    families.split(",").map((family) => document.fonts.load(`${style} ${family.trim()}`, text))));
}

/**
 * Draws the card and hands the PNG to `show`. A slow network does not keep the
 * picture waiting: after a few seconds it is drawn with what has arrived, and
 * drawn again once the reader's fonts and the seal are in, so it always ends
 * in Amiri.
 */
export async function renderShareCard(
  content: ShareCardContent,
  fonts: ShareCardFonts,
  logoUrl: string,
  show: (png: Blob) => void,
): Promise<void> {
  const size = arabicSize(content.arabic);
  const sample = `${content.title} ${content.translation} ${content.reference} ${SITE}`;
  const assets: { logo: HTMLImageElement | null } = { logo: null };
  const loaded = Promise.all([
    loadImage(logoUrl).then((logo) => { assets.logo = logo; }),
    loadFonts([
      [`${size}px`, fonts.arabic, content.arabic],
      ["600 17px", fonts.text, sample],
      ["15px", fonts.text, sample],
    ]),
  ]);
  const inTime = await Promise.race([
    loaded.then(() => true),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), ASSET_WAIT_MS)),
  ]);
  show(await drawCard(content, fonts, size, assets.logo));
  if (inTime) return;
  await loaded;
  show(await drawCard(content, fonts, size, assets.logo));
}

function drawCard(
  content: ShareCardContent,
  fonts: ShareCardFonts,
  size: number,
  logo: HTMLImageElement | null,
): Promise<Blob> {
  const fontFaces = [
    `${size}px ${fonts.arabic}`,
    `600 17px ${fonts.text}`,
    `15px ${fonts.text}`,
  ];
  const canvas = document.createElement("canvas");
  canvas.width = WIDTH * PIXEL_RATIO;
  canvas.height = HEIGHT * PIXEL_RATIO;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas 2D is unavailable");
  context.scale(PIXEL_RATIO, PIXEL_RATIO);
  context.textBaseline = "middle";

  const background = context.createLinearGradient(0, 0, 0, HEIGHT);
  background.addColorStop(0, "#0b4a3c");
  background.addColorStop(1, "#062a22");
  context.fillStyle = background;
  context.fillRect(0, 0, WIDTH, HEIGHT);

  context.strokeStyle = "rgba(226, 182, 101, 0.7)";
  context.lineWidth = 1;
  roundedRect(context, 18.5, 18.5, WIDTH - 37, HEIGHT - 37, 22);
  context.stroke();

  // Inside the frame: 26 px at the sides, 22 at the top and 20 at the bottom.
  const left = 44;
  const right = WIDTH - 44;
  const width = right - left;
  const top = 40;
  const bottom = HEIGHT - 38;
  const pageRtl = document.documentElement.dir === "rtl";

  // The seal and the title, in the reading direction of the page.
  context.font = fontFaces[1];
  const title: Block = {
    lines: titleLines(context, content.title, width - 56, 2),
    font: fontFaces[1],
    lineHeight: 17 * 1.25,
    rtl: pageRtl,
  };
  const headerHeight = Math.max(44, title.lines.length * title.lineHeight);
  if (logo) context.drawImage(logo, pageRtl ? right - 44 : left, top + (headerHeight - 44) / 2, 44, 44);
  context.fillStyle = GOLD;
  drawBlock(
    context,
    title,
    pageRtl ? right - 56 : left + 56,
    top + (headerHeight - title.lines.length * title.lineHeight) / 2,
    pageRtl ? "right" : "left",
  );

  // From the bottom up: the site, a gold rule, the source and the meaning.
  context.font = `600 14px ${fonts.text}`;
  context.letterSpacing = "1.2px";
  context.direction = "ltr";
  context.textAlign = "center";
  context.fillText(SITE, WIDTH / 2, bottom - 8.5);
  context.letterSpacing = "0px";
  const ruleY = bottom - 17 - 10;
  context.fillStyle = "rgba(226, 182, 101, 0.4)";
  context.fillRect(left, ruleY - 1, width, 1);

  let cursor = ruleY - 1 - 14;
  const reference = block(context, content.reference, `12px ${fonts.text}`, 12 * 1.3, width, 2);
  cursor -= reference.lines.length * reference.lineHeight;
  context.fillStyle = "rgba(255, 255, 255, 0.6)";
  drawBlock(context, reference, WIDTH / 2, cursor, "center");

  const translation = block(context, content.translation, fontFaces[2], 15 * 1.45, width, 6);
  if (translation.lines.length > 0) {
    cursor -= 12 + translation.lines.length * translation.lineHeight;
    context.fillStyle = "rgba(255, 255, 255, 0.88)";
    drawBlock(context, translation, WIDTH / 2, cursor, "center");
  }

  // The Arabic is centred in the space left. A passage too long for it gets a
  // smaller script, down to 14 px, and only then is cut.
  const areaTop = top + headerHeight + 8;
  const areaHeight = cursor - 8 - areaTop;
  const arabicBlock = (fontSize: number, maxLines: number) =>
    block(context, content.arabic, `${fontSize}px ${fonts.arabic}`, fontSize * 1.9, width, maxLines);
  let fontSize = size;
  let arabic = arabicBlock(fontSize, Infinity);
  while (fontSize > 14 && (arabic.lines.length > 14 || arabic.lines.length * arabic.lineHeight > areaHeight)) {
    fontSize -= 1;
    arabic = arabicBlock(fontSize, Infinity);
  }
  const maxLines = Math.max(1, Math.min(14, Math.floor(areaHeight / arabic.lineHeight)));
  if (arabic.lines.length > maxLines) arabic = arabicBlock(fontSize, maxLines);
  context.fillStyle = IVORY;
  drawBlock(
    context,
    { ...arabic, rtl: true },
    WIDTH / 2,
    areaTop + (areaHeight - arabic.lines.length * arabic.lineHeight) / 2,
    "center",
  );

  return new Promise((resolve, reject) => {
    canvas.toBlob((png) => (png ? resolve(png) : reject(new Error("PNG encoding failed"))), "image/png");
  });
}
