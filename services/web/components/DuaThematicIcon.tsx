import { createElement } from "react";
import shapes from "../lib/dua-topic-icons.json";
import { DuaTimeIcon } from "./DuaTimeIcon";

export function DuaThematicIcon({ topic }: { topic: string }) {
  if (topic === "morning" || topic === "evening") return <DuaTimeIcon evening={topic === "evening"} />;
  const paths = shapes[topic as keyof typeof shapes];
  if (!paths) return null;
  return <span className="dua-topic-icon dua-time-icon" aria-hidden="true">
    <svg viewBox="0 0 64 64" fill="none">
      {paths.map(({ tag, ...attributes }, index) => createElement(tag, { ...attributes, key: index }))}
    </svg>
  </span>;
}
