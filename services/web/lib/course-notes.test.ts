import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { renderToStaticMarkup } from "react-dom/server";

import { renderCourseNotes } from "./course-notes.ts";
import { parseNoteBlocks, type NoteBlock, type Segment } from "./thematic-courses.ts";

// The shared «markup → blocks» examples: the backend checks its parser on them,
// the clients check that they draw every block type, direction and Arabic run.
const { cases } = JSON.parse(
  readFileSync(new URL("../../../docs/courses/notes-markup.cases.json", import.meta.url), "utf8"),
) as { cases: { name: string; blocks: unknown }[] };

function html(blocks: NoteBlock[]): string {
  return renderToStaticMarkup(renderCourseNotes(blocks, { note: "Важно" }));
}

function escape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("\"", "&quot;");
}

function segmentHtml(segment: Segment): string {
  const content = segment.lang === "ar"
    ? `<bdi lang="ar" class="course-notes-ar">${escape(segment.text)}</bdi>`
    : escape(segment.text);
  return segment.bold ? `<strong>${content}</strong>` : content;
}

function linesHtml(lines: Segment[][]): string {
  return lines.map((line) => line.map(segmentHtml).join("")).join("<br/>");
}

function expectedHtml(block: NoteBlock): string {
  switch (block.type) {
    case "heading":
      return `<h3 dir="${block.dir}" class="course-notes-heading">${block.text.map(segmentHtml).join("")}</h3>`;
    case "paragraph":
      return `<p dir="${block.dir}">${linesHtml(block.lines)}</p>`;
    case "list": {
      const tag = block.ordered ? "ol" : "ul";
      const items = block.items.map((item) => `<li>${item.map(segmentHtml).join("")}</li>`).join("");
      return `<${tag} dir="${block.dir}" class="course-notes-list">${items}</${tag}>`;
    }
    case "quote":
      return `<figure dir="${block.dir}" class="course-notes-quote"><blockquote>${linesHtml(block.lines)}</blockquote>`
        + (block.source === null ? "" : `<figcaption dir="auto">— ${escape(block.source)}</figcaption>`)
        + "</figure>";
    case "note":
      return `<aside dir="${block.dir}" class="course-notes-note"><strong class="course-notes-note-label">Важно</strong> ${linesHtml(block.lines)}</aside>`;
  }
}

test("every shared notes case draws its blocks, directions and Arabic runs", () => {
  const types = new Set<string>();
  for (const { name, blocks: raw } of cases) {
    const blocks = parseNoteBlocks(raw);
    blocks.forEach((block) => types.add(block.type));
    assert.equal(
      html(blocks),
      `<div class="course-notes">${blocks.map(expectedHtml).join("")}</div>`,
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
