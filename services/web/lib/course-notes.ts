// Draws the notes blocks of a thematic lesson (docs/courses/README.md, «Конспект») as
// plain server HTML: text only, no innerHTML, no client JS. Written without JSX so that
// `node --test` can render it. A «!» or «?» note opens with the HTML popover: the browser
// closes it on Escape and on a tap outside, with no script of ours.

import { createElement, Fragment, type ReactNode } from "react";

import { noteLinkPath, type NoteBlock, type Segment, type SegmentNote } from "./thematic-courses.ts";

export type CourseNotesLabels = {
  note: string;
  warning: string;
  help: string;
  close: string;
  newTab: string;
};

export type CourseNotesOptions = {
  /** Internal links get the language: `/{locale}/…`. */
  locale: string;
  /** Prefix of the notes' popover ids, unique among the notes of a page. */
  id?: string;
  /** Arabic runs in the interface font: the tajweed course in Arabic keeps its look. */
  plainArabic?: boolean;
};

type Context = { labels: CourseNotesLabels; options: CourseNotesOptions; id: string };

function text(item: Segment, key: number, context: Context): ReactNode {
  // Arabic runs keep their own direction inside a line of another script.
  const content = item.lang === "ar" && !context.options.plainArabic
    ? createElement("bdi", { lang: "ar", className: "course-notes-ar" }, item.text)
    : item.text;
  return item.bold
    ? createElement("strong", { key }, content)
    : createElement(Fragment, { key }, content);
}

/** The icon after a word and its popover: a heading, «Close» and the note's text. */
function mark(note: SegmentNote, key: number, id: string, context: Context): ReactNode {
  const { labels } = context;
  const label = note.kind === "warning" ? labels.warning : labels.help;
  return createElement(
    Fragment,
    { key },
    createElement(
      "button",
      {
        type: "button",
        className: `course-mark is-${note.kind}`,
        popoverTarget: id,
        "aria-label": label,
        title: label,
        "data-testid": "course-mark",
      },
      createElement("span", { "aria-hidden": true }, note.kind === "warning" ? "!" : "?"),
    ),
    createElement(
      "span",
      {
        id,
        popover: "auto",
        className: `course-mark-popover is-${note.kind}`,
        role: "dialog",
        "aria-label": label,
        "data-testid": "course-mark-popover",
      },
      createElement(
        "span",
        { className: "course-mark-head" },
        createElement("strong", null, label),
        createElement(
          "button",
          {
            type: "button",
            className: "course-mark-close",
            popoverTarget: id,
            popoverTargetAction: "hide",
            "aria-label": labels.close,
            title: labels.close,
          },
          createElement("span", { "aria-hidden": true }, "×"),
        ),
      ),
      createElement(
        "span",
        { className: "course-mark-text" },
        ...note.text.map((item, index) => text(item, index, context)),
      ),
    ),
  );
}

/** One line: neighbouring segments of one link become one `<a>`. */
function line(items: Segment[], context: Context, id: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index]!;
    if (item.note) {
      nodes.push(mark(item.note, index, `${id}-${index}`, context));
      continue;
    }
    if (!item.link) {
      nodes.push(text(item, index, context));
      continue;
    }
    const { href, kind } = item.link;
    const parts: ReactNode[] = [];
    let end = index;
    while (end < items.length && items[end]!.link?.href === href && !items[end]!.note) {
      parts.push(text(items[end]!, end, context));
      end += 1;
    }
    nodes.push(
      kind === "external"
        ? createElement(
          "a",
          { key: index, href, className: "course-notes-link", target: "_blank", rel: "noopener noreferrer" },
          ...parts,
          createElement("span", { className: "course-notes-external", "aria-hidden": true }, "↗"),
          createElement("span", { className: "sr-only" }, ` (${context.labels.newTab})`),
        )
        : createElement(
          "a",
          { key: index, href: `/${context.options.locale}${noteLinkPath(href)}`, className: "course-notes-link" },
          ...parts,
        ),
    );
    index = end - 1;
  }
  return nodes;
}

/** Lines of one block, a line break between them. */
function lines(items: Segment[][], context: Context, id: string): ReactNode[] {
  return items.flatMap((items, index) => [
    ...(index ? [createElement("br", { key: `br-${index}` })] : []),
    createElement(Fragment, { key: index }, ...line(items, context, `${id}-${index}`)),
  ]);
}

function block(item: NoteBlock, key: number, context: Context): ReactNode {
  const { dir } = item;
  const id = `${context.id}-${key}`;
  switch (item.type) {
    case "heading":
      return createElement("h3", { key, dir, className: "course-notes-heading" }, ...line(item.text, context, id));
    case "paragraph":
      return createElement("p", { key, dir }, ...lines(item.lines, context, id));
    case "list":
      return createElement(
        item.ordered ? "ol" : "ul",
        { key, dir, className: "course-notes-list" },
        ...item.items.map((entry, index) => createElement("li", { key: index }, ...line(entry, context, `${id}-${index}`))),
      );
    case "quote":
      return createElement(
        "figure",
        { key, dir, className: "course-notes-quote" },
        createElement("blockquote", null, ...lines(item.lines, context, id)),
        item.source === null
          ? null
          : createElement("figcaption", { dir: "auto" }, `— ${item.source}`),
      );
    case "note":
      return createElement(
        "aside",
        { key, dir, className: "course-notes-note" },
        createElement("strong", { className: "course-notes-note-label" }, context.labels.note),
        " ",
        ...lines(item.lines, context, id),
      );
  }
}

export function renderCourseNotes(
  blocks: NoteBlock[],
  labels: CourseNotesLabels,
  options: CourseNotesOptions,
): ReactNode {
  const context = { labels, options, id: options.id ?? "course-note" };
  return createElement(
    "div",
    { className: "course-notes" },
    ...blocks.map((item, index) => block(item, index, context)),
  );
}
