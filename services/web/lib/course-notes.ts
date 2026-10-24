// Draws the notes blocks of a thematic lesson (docs/courses/README.md, «Конспект») as
// plain server HTML: text only, no innerHTML, no client JS. Written without JSX so that
// `node --test` can render it.

import { createElement, Fragment, type ReactNode } from "react";

import type { NoteBlock, Segment } from "./thematic-courses.ts";

export type CourseNotesLabels = { note: string };

function segment(item: Segment, key: number): ReactNode {
  // Arabic runs keep their own direction inside a line of another script.
  const content = item.lang === "ar"
    ? createElement("bdi", { lang: "ar", className: "course-notes-ar" }, item.text)
    : item.text;
  return item.bold
    ? createElement("strong", { key }, content)
    : createElement(Fragment, { key }, content);
}

function line(items: Segment[]): ReactNode[] {
  return items.map(segment);
}

/** Lines of one block, a line break between them. */
function lines(items: Segment[][]): ReactNode[] {
  return items.flatMap((items, index) => [
    ...(index ? [createElement("br", { key: `br-${index}` })] : []),
    createElement(Fragment, { key: index }, ...line(items)),
  ]);
}

function block(item: NoteBlock, key: number, labels: CourseNotesLabels): ReactNode {
  const { dir } = item;
  switch (item.type) {
    case "heading":
      return createElement("h3", { key, dir, className: "course-notes-heading" }, ...line(item.text));
    case "paragraph":
      return createElement("p", { key, dir }, ...lines(item.lines));
    case "list":
      return createElement(
        item.ordered ? "ol" : "ul",
        { key, dir, className: "course-notes-list" },
        ...item.items.map((entry, index) => createElement("li", { key: index }, ...line(entry))),
      );
    case "quote":
      return createElement(
        "figure",
        { key, dir, className: "course-notes-quote" },
        createElement("blockquote", null, ...lines(item.lines)),
        item.source === null
          ? null
          : createElement("figcaption", { dir: "auto" }, `— ${item.source}`),
      );
    case "note":
      return createElement(
        "aside",
        { key, dir, className: "course-notes-note" },
        createElement("strong", { className: "course-notes-note-label" }, labels.note),
        " ",
        ...lines(item.lines),
      );
  }
}

export function renderCourseNotes(blocks: NoteBlock[], labels: CourseNotesLabels): ReactNode {
  return createElement(
    "div",
    { className: "course-notes" },
    ...blocks.map((item, index) => block(item, index, labels)),
  );
}
