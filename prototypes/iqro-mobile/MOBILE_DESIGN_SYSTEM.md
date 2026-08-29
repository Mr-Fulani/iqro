# IQRO mobile design system

## 1. Character

The visual language is calm, tactile, and editorial: deep emerald for action and trust, warm sand for reflective surfaces, quiet lavender as a supporting accent, and generous neutral space. Ornament is restrained so Arabic text, progress, and the next action remain dominant.

The prototype uses system fonts and Georgia as safe local stand-ins. Production must select and license an Arabic/Quran typeface only after glyph, waqf-mark, tajweed, diacritic, and platform rendering QA.

## 2. Semantic tokens

| Token group | Light intent | Dark intent |
| --- | --- | --- |
| `--bg`, `--bg-raised` | warm off-white canvas | deep green-black canvas |
| `--panel`, `--panel-soft` | primary and quiet surfaces | elevated charcoal-green surfaces |
| `--text`, `--text-soft`, `--text-faint` | high/medium/low emphasis | accessible warm-white hierarchy |
| `--emerald-700/800` | primary action and strong Quran accents | brighter action and focus colors |
| `--sand-soft`, `--lavender-soft` | supporting category surfaces | low-chroma tinted surfaces |
| `--line`, `--line-strong` | dividers and controls | visible but quiet separators |
| `--danger`, `--warning`, `--success` | semantic feedback | theme-adjusted semantic feedback |

Components consume semantic variables instead of raw palette values. This lets Flutter map the same design decisions to `ColorScheme` extensions and platform contrast rules.

## 3. Type scale

| Role | Prototype range | Use |
| --- | --- | --- |
| Display | 28–38 px | onboarding and player focus |
| Screen title | 21–27 px | top-level destinations |
| Section title | 15–19 px | grouped content |
| Body | 11–15 px in the scaled device prototype | descriptions and settings |
| Label | 9–12 px | navigation, chips, metadata |
| Quran Arabic | 28–41 px, generous line-height | ayahs and Mushaf page |
| Dua Arabic | 23–30 px | entry content |

Production Flutter should use semantic text styles with `TextScaler`, test 100%, 130%, and 200% scaling, and avoid truncating content that carries meaning. The small numbers above are part of a desktop-hosted scaled prototype; the Flutter handoff should use platform-equivalent logical sizes and accessibility QA, not copy CSS pixels mechanically.

## 4. Spacing, shape, and elevation

- Base spacing unit: 4 px; common gaps: 8, 12, 16, 20, 24.
- Screen gutters: 16–18 px at mobile widths.
- Minimum target: 44×44 px; primary buttons are at least 50 px high.
- Card radius: 18–24 px; compact controls: 12–16 px; sheets: 28 px top radius.
- Border is preferred over shadow for ordinary hierarchy. Floating player, sheet, and modal may use a soft elevation.
- The five-item bottom navigation is fixed, with the global mini-player anchored above it.

## 5. Core components

| Component | Variants and behavior |
| --- | --- |
| App top bar | title, optional eyebrow, back, one or two actions; uses logical start/end |
| Progress hero | daily goal, next prayer, or resume action; one dominant CTA |
| Content card | neutral, emerald, sand, lavender; disabled future card uses `Soon` badge |
| Segmented control | Text/Mushaf and filters; selected state uses label, fill, and contrast |
| Ayah card | Arabic, ayah marker, bookmark, play, translation/footnote availability |
| Mushaf page | full-page Arabic flow, zoom, selected ayah highlight, bottom controls |
| Compact player | content identity, reciter, play/pause; never overlaps bottom navigation |
| Full player | artwork, progress, transport, repeat/range, speed, pause, timer |
| Toggle row | title, supporting copy, accessible switch state; prayer toggles are independent |
| Bottom sheet | drag handle, title, scrollable body, safe-area padding |
| Confirmation dialog | destructive title, consequence, cancel and explicit action |
| Status banner | icon, plain-language title/body, recovery action when available |
| Toast | short confirmation; never the only record of a critical failure |

## 6. Interaction rules

1. One visually dominant action per card or sheet.
2. Persistent choices (language, theme, reciter, Mushaf, reader mode) update immediately and survive navigation.
3. Destructive or irreversible actions require confirmation. Memorization reset demonstrates this pattern.
4. Disabled future features remain noninteractive and carry a visible `Soon` label.
5. Player continuity is global, but content-source changes stop incompatible playback.
6. Bookmark/favorite controls expose pressed state to assistive technology.
7. Prayer notification controls are separate per prayer; the after-prayer prompt is a sixth, separate rule.

## 7. State patterns

| State | Presentation | Recovery |
| --- | --- | --- |
| Loading | stable skeleton/banner, no layout jump | wait/cancel only when meaningful |
| Offline | calm banner; local actions remain available | retry automatically and expose manual retry |
| API error | state-specific copy, no raw exception | retry or return to cached content |
| Session expired | preserve pending local work | sign in again, then resume sync |
| Sync conflict | explain the two outcomes in plain language | choose local/remote only where policy cannot decide |
| Notification denied | no repeated system prompt | link to platform settings after user action |
| Location denied | allow manual city/timezone | reopen platform permission from settings |
| No audio | preserve reader flow | change reciter/track or retry |
| No offline copy | show size/network requirement | download when a package contract exists |
| Empty favorites/history | explain benefit and link to content | direct CTA, not decorative emptiness |

## 8. RTL and localization

- Use start/end, inline/block, and direction-aware icons; avoid hard-coded left/right layout values.
- Back arrows mirror in RTL, while media play, checkmarks, and religious source content do not.
- Numbers may remain locale-formatted according to product policy; Arabic Quran text always remains RTL and centered/justified by its content needs.
- Labels are allowed to wrap. Fixed-width controls must be tested in RU, EN, AR, and TR.
- Translation edition and tafsir source names are content, not UI strings, and require editorial metadata.

## 9. Flutter mapping

- CSS semantic variables → `ThemeExtension` and `ColorScheme`.
- Cards/buttons/chips/sheets → shared design-system widgets in a presentation package.
- Root `dir` → `Directionality` from app locale; use directional paddings and radii.
- `localStorage` mock → Drift/SQLite local projections plus secure storage for credentials.
- Prototype store → feature controllers (for example Riverpod/Bloc) with immutable state.
- CSS media queries → responsive constraints and safe-area widgets, not device-name checks.
