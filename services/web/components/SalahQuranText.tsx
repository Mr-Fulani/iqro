import type { ReactNode } from "react";

import type { SalahQuranAyah } from "../lib/salah";

const arabicNumber = new Intl.NumberFormat("ar-EG", { useGrouping: false });

/** An ayah's words and end sign as the selected Mushaf writes them. */
export type SalahAyahGlyphs = { words: ReactNode; end: ReactNode };

/**
 * The ayahs of a formula as the Quran readers draw them: the basmala above,
 * each ayah on its own lines with its end sign. `glyphs` gives the ayahs the
 * selected Mushaf's script once it has loaded (SalahQuranScript); until then,
 * and on the server, the plain text with ﴿١﴾ is drawn, as in the readers.
 */
export function SalahQuranText({ ayahs, glyphs }: { ayahs: SalahQuranAyah[]; glyphs?: (SalahAyahGlyphs | null)[] | null }) {
  const opening = ayahs[0]?.opening;
  return (
    <div className="salah-arabic salah-quran" lang="ar" dir="rtl">
      {opening ? <p className="salah-quran-opening">{opening}</p> : null}
      {ayahs.map((ayah, index) => {
        const drawn = glyphs?.[index];
        return (
          <p key={ayah.number} data-ayah={ayah.number}>
            {drawn ? drawn.words : ayah.text}
            {/* A no-break space keeps the sign with the last word. */}
            {"\u00A0"}
            <span className="ayah-end-marker">{drawn?.end ?? `\uFD3F${arabicNumber.format(ayah.number)}\uFD3E`}</span>
          </p>
        );
      })}
    </div>
  );
}
