import { createElement } from "react";
import shapes from "../lib/home-section-icons.json";

/**
 * A Home section's icon: one thin line on a 64 grid, shared with the app
 * (clients/iqro_mobile/lib/features/home/home_section_icons.g.dart).
 * `currentColor` in the art is the element's text colour.
 */
export function HomeSectionIcon({ section }: { section: string }) {
  const paths = shapes[section as keyof typeof shapes];
  if (!paths) return null;
  return (
    <svg className="home-section-icon" viewBox="0 0 64 64" aria-hidden="true">
      {paths.map(({ tag, ...attributes }, index) => createElement(tag, { ...attributes, key: index }))}
    </svg>
  );
}
