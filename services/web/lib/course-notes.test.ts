import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { renderToStaticMarkup } from "react-dom/server";

import { renderCourseNotes } from "./course-notes.ts";
import { noteLinkPath, parseNoteBlocks, type NoteBlock, type Segment } from "./thematic-courses.ts";

// The shared «markup → blocks» examples: the backend checks its parser on them,
// the clients check that they draw every block type, direction, Arabic run, note and link.
const { cases } = JSON.parse(
  readFileSync(new URL("../../../docs/courses/notes-markup.cases.json", import.meta.url), "utf8"),
) as { cases: { name: string; blocks: unknown }[] };

const LABELS = { note: "Важно", warning: "Внимание", help: "Пояснение", close: "Закрыть", newTab: "новая вкладка" };

function html(blocks: NoteBlock[]): string {
  return renderToStaticMarkup(renderCourseNotes(blocks, LABELS, { locale: "ru" }));
}

function escape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("\"", "&quot;");
}

function textHtml(segment: Segment): string {
  const content = segment.lang === "ar"
    ? `<bdi lang="ar" class="course-notes-ar">${escape(segment.text)}</bdi>`
    : escape(segment.text);
  return segment.bold ? `<strong>${content}</strong>` : content;
}

function noteHtml(segment: Segment, id: string): string {
  const { kind, text } = segment.note!;
  const label = kind === "warning" ? "Внимание" : "Пояснение";
  return `<button type="button" class="course-mark is-${kind}" popoverTarget="${id}" aria-label="${label}" title="${label}" data-testid="course-mark"><span aria-hidden="true">${kind === "warning" ? "!" : "?"}</span></button>`
    + `<span id="${id}" popover="auto" class="course-mark-popover is-${kind}" role="dialog" aria-label="${label}" data-testid="course-mark-popover">`
    + `<span class="course-mark-head"><strong>${label}</strong><button type="button" class="course-mark-close" popoverTarget="${id}" popoverTargetAction="hide" aria-label="Закрыть" title="Закрыть"><span aria-hidden="true">×</span></button></span>`
    + `<span class="course-mark-text">${text.map(textHtml).join("")}</span></span>`;
}

/** A line as the site draws it: neighbouring segments of one link in one `<a>`. */
function lineHtml(line: Segment[], id: string): string {
  let result = "";
  for (let index = 0; index < line.length; index += 1) {
    const segment = line[index]!;
    if (segment.note) {
      result += noteHtml(segment, `${id}-${index}`);
    } else if (!segment.link) {
      result += textHtml(segment);
    } else {
      const { href, kind } = segment.link;
      let inner = "";
      while (index < line.length && line[index]!.link?.href === href) inner += textHtml(line[index++]!);
      index -= 1;
      result += kind === "external"
        ? `<a href="${escape(href)}" class="course-notes-link" target="_blank" rel="noopener noreferrer">${inner}<span class="course-notes-external" aria-hidden="true">↗</span><span class="sr-only"> (новая вкладка)</span></a>`
        : `<a href="${escape(`/ru${noteLinkPath(href)}`)}" class="course-notes-link">${inner}</a>`;
    }
  }
  return result;
}

function linesHtml(lines: Segment[][], id: string): string {
  return lines.map((line, index) => lineHtml(line, `${id}-${index}`)).join("<br/>");
}

function expectedHtml(block: NoteBlock, index: number): string {
  const id = `course-note-${index}`;
  switch (block.type) {
    case "heading":
      return `<h3 dir="${block.dir}" class="course-notes-heading">${lineHtml(block.text, id)}</h3>`;
    case "paragraph":
      return `<p dir="${block.dir}">${linesHtml(block.lines, id)}</p>`;
    case "list": {
      const tag = block.ordered ? "ol" : "ul";
      const items = block.items.map((item, item_) => `<li>${lineHtml(item, `${id}-${item_}`)}</li>`).join("");
      return `<${tag} dir="${block.dir}" class="course-notes-list">${items}</${tag}>`;
    }
    case "quote":
      return `<figure dir="${block.dir}" class="course-notes-quote"><blockquote>${linesHtml(block.lines, id)}</blockquote>`
        + (block.source === null ? "" : `<figcaption dir="auto">— ${escape(block.source)}</figcaption>`)
        + "</figure>";
    case "note":
      return `<aside dir="${block.dir}" class="course-notes-note"><strong class="course-notes-note-label">Важно</strong> ${linesHtml(block.lines, id)}</aside>`;
  }
}

test("every shared notes case draws its blocks, directions and Arabic runs", () => {
  const types = new Set<string>();
  for (const { name, blocks: raw } of cases) {
    const blocks = parseNoteBlocks(raw);
    blocks.forEach((block) => types.add(block.type));
    assert.equal(
      html(blocks),
      `<div class="course-notes">${blocks.map((block, index) => expectedHtml(block, index)).join("")}</div>`,
      name,
    );
  }
  assert.deepEqual([...types].sort(), ["heading", "list", "note", "paragraph", "quote"]);
});

test("Arabic runs are isolated, bold Arabic stays bold, line breaks stay inside a paragraph", () => {
  const byName = new Map(cases.map((item) => [item.name, parseNoteBlocks(item.blocks)]));
  assert.equal(
    html(byName.get("inline_arabic_word")!),
    '<div class="course-notes"><p dir="ltr">Пост (<bdi lang="ar" class="course-notes-ar">الصوم</bdi>) — обязанность.</p></div>',
  );
  assert.equal(
    html(byName.get("bold_arabic")!),
    '<div class="course-notes"><p dir="rtl"><strong><bdi lang="ar" class="course-notes-ar">الصوم</bdi></strong></p></div>',
  );
  assert.match(html(byName.get("paragraph_bold_and_line_break")!), /<strong>решение сердца<\/strong>\.<br\/>Вторая строка/);
  assert.match(html(byName.get("quote_arabic_with_source")!), /<figure dir="rtl"[^>]*><blockquote><bdi lang="ar"/);
  assert.match(html(byName.get("quote_arabic_with_source")!), /<figcaption dir="auto">— Коран, 2:183<\/figcaption>/);
  assert.equal(html(byName.get("empty")!), '<div class="course-notes"></div>');
});

test("notes are text: markup in a segment is escaped, never parsed", () => {
  const markup = html([{ type: "paragraph", dir: "ltr", lines: [[{ text: "<img src=x onerror=alert(1)>" }]] }]);
  assert.equal(markup, '<div class="course-notes"><p dir="ltr">&lt;img src=x onerror=alert(1)&gt;</p></div>');
});

test("every note and link of the shared cases reaches the page", () => {
  let notes = 0;
  let links = 0;
  for (const { blocks: raw } of cases) {
    const blocks = parseNoteBlocks(raw);
    const rows = blocks.flatMap((block) => (block.type === "heading" ? [block.text] : "lines" in block ? block.lines : block.items));
    notes += rows.flat().filter((segment) => segment.note).length;
    links += rows.flat().filter((segment) => segment.link).length;
  }
  assert.ok(notes >= 8 && links >= 8, `${notes} notes, ${links} links`);
});

test("a note is a labelled button that opens its own popover after the word", () => {
  const byName = new Map(cases.map((item) => [item.name, parseNoteBlocks(item.blocks)]));
  const markup = html(byName.get("note_warning_after_word")!);
  assert.match(markup, /в сердце<button type="button" class="course-mark is-warning" popoverTarget="course-note-0-0-1" aria-label="Внимание"/);
  assert.match(markup, /<span id="course-note-0-0-1" popover="auto"[^>]*role="dialog"[^>]*>.*Произносить его вслух не обязательно\.<\/span><\/span> перед молитвой/);
  const help = html(byName.get("note_help_with_bold_and_arabic")!);
  assert.match(help, /aria-label="Пояснение"/);
  assert.match(help, /<strong><bdi lang="ar" class="course-notes-ar">الصوم<\/bdi><\/strong>/);
  // Every popover of a page has its own id.
  const ids = html(byName.get("notes_in_heading_list_quote_and_callout")!).match(/ id="[^"]+"/g)!;
  assert.equal(new Set(ids).size, 4);
});

test("internal links get the language, an ayah opens in the reader, external ones a new tab", () => {
  const byName = new Map(cases.map((item) => [item.name, parseNoteBlocks(item.blocks)]));
  assert.match(html(byName.get("link_internal_ayah")!), /<a href="\/ru\/quran\?surah=2&amp;ayah=255" class="course-notes-link">аят аль-Курси<\/a>/);
  const sections = html(byName.get("link_internal_sections")!);
  assert.match(sections, /href="\/ru\/quran\?surah=1"/);
  assert.match(sections, /href="\/ru\/courses\/ramadan\/namerenie"/);
  assert.match(sections, /href="\/ru\/tajweed\/izhar"/);
  assert.match(html(byName.get("link_external_allowed")!), /<a href="https:\/\/sunnah\.com\/bukhari:1" class="course-notes-link" target="_blank" rel="noopener noreferrer">sunnah\.com<span/);
  assert.match(html(byName.get("link_with_bold_label")!), /<a href="\/ru\/courses\/ramadan" class="course-notes-link"><strong>Важная<\/strong> тема<\/a>/);
  assert.equal(
    renderToStaticMarkup(renderCourseNotes(byName.get("link_internal_ayah")!, LABELS, { locale: "ar" })).includes('href="/ar/quran?surah=2&amp;ayah=255"'),
    true,
  );
});

test("a link the site cannot follow and a broken note stay text", () => {
  const blocks = parseNoteBlocks([{
    type: "paragraph",
    dir: "ltr",
    lines: [[
      { text: "a", link: { href: "javascript:alert(1)", kind: "external" } },
      { text: "b", link: { href: "/admin", kind: "internal" } },
      { text: "c", link: { href: "http://sunnah.com", kind: "external" } },
      { text: "", note: { kind: "other", text: [{ text: "x" }] } },
      { text: "", note: { kind: "help", text: [] } },
    ]],
  }]);
  assert.equal(html(blocks), '<div class="course-notes"><p dir="ltr">abc</p></div>');
});

test("an Arabic tajweed lesson keeps the interface font and its own popover ids", () => {
  const byName = new Map(cases.map((item) => [item.name, parseNoteBlocks(item.blocks)]));
  const markup = renderToStaticMarkup(
    renderCourseNotes(byName.get("note_help_with_bold_and_arabic")!, LABELS, { locale: "ar", id: "tajweed-how", plainArabic: true }),
  );
  assert.doesNotMatch(markup, /<bdi/);
  assert.match(markup, /id="tajweed-how-0-0-1"/);
});
