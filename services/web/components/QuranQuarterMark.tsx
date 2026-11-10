"use client";

import Image from "next/image";

/**
 * The pill that tells the reader a new rub al-hizb quarter starts here. The
 * live region stays mounted so screen readers announce each new label.
 */
export function QuranQuarterMark({ label }: { label: string | null }) {
  return (
    <div className="quran-quarter-mark-region" role="status" aria-live="polite">
      {label && (
        <div className="quran-quarter-mark" key={label} data-testid="quran-quarter-mark">
          <Image src="/iqro-wax-seal-128.webp" alt="" width={36} height={36} unoptimized />
          <span>{label}</span>
        </div>
      )}
    </div>
  );
}
