import type { LegalSection } from "@/lib/legal-content";

export function LegalDocument({
  title,
  description,
  updated,
  sections,
}: {
  title: string;
  description: string;
  updated: string;
  sections: LegalSection[];
}) {
  return (
    <article className="seo-quran-page legal-document">
      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">Quran Platform</p>
          <h1>{title}</h1>
          <p>{description}</p>
          <p className="seo-content-version">{updated}</p>
        </div>
      </header>
      {sections.map((section) => (
        <section className="surface legal-section" key={section.title}>
          <h2 className="surface-title">{section.title}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
          {section.bullets && (
            <ul>
              {section.bullets.map((item) => <li key={item}>{item}</li>)}
            </ul>
          )}
        </section>
      ))}
    </article>
  );
}
