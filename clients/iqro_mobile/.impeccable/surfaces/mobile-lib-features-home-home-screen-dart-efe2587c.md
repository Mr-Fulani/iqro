---
version: 1
slug: "mobile-lib-features-home-home-screen-dart-efe2587c"
primary_target: "clients/iqro_mobile/lib/features/home/home_screen.dart"
related_targets: ["clients/iqro_mobile/lib/features/more/more_screen.dart"]
---

# Home and More

Mode: Operate. Android Flutter. Preserve the existing design system; no identity replacement.

## Direction contract

THESIS: Daily practice is visible as useful state and direct actions. Prayer and continuing reading lead; other real functions are below, as confirmed by the user.

OWN-WORLD: Inherit IQRO emerald/gold, light and dark Material themes, outlined Material icons, rounded filled and bordered cards. Theme tokens remain authoritative.

STORY: Find the next prayer, return to the saved ayah, understand today's plan, then open audio, duas, memorization, reading after prayer, favorites, Hijri calendar, reminders and offline downloads.

FIRST VIEWPORT: Compact IQRO header. Prayer name and time lead, followed by a compact saved-reading card with an explicit read action. A compact daily-plan progress block follows; additional tools form smaller functional groups below.

FORM: User-pinned hierarchy, composition within the incumbent world. Direction key iqro-home-prayer-reading; no new-world roll. User approved comp A: clients/iqro_mobile/.impeccable/mocks/home-a.png. Build comp-led this session; no permanent workflow default recorded. Preserve the stacked prayer, reading, plan, two-column tools and utility-list topology. Correct generated sample copy to product truth: After prayer is a reading plan, bookmarks contain ayahs and duas, and the countdown uses actual time. Native touch targets and larger text may increase the scroll height.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Scope and verification

More: replace fixed-aspect grid sizing with content-sized rows; calendar title must fit long translations and large text. All four locales and both themes retain real actions. Home retains account scoping, loading/empty states and existing routes; no API repairs or storage cleanup.

## Native implementation notes

Android Material typography and the app's actual fonts remain in use. The CLI's web font fingerprint suggested Delius Unicase for clock digits; this is a measurement artifact, not a native font change. The selected comp uses UI geometry and icons only; no raster plates are owed. CSS scaffolding is reference evidence only, not app code. Body copy is corrected to existing product behavior and translated into all four locales. Native minimum touch targets and font scaling can extend the scroll beyond the illustrative comp; navigation and active mini-player retain their existing reserved space.

## Validation

48 focused layout/widget checks passed after the final component edit (four locales, both themes, normal and enlarged type, calendar opening and dashboard actions). Four home data-helper tests also passed on this revision's unchanged helpers. Flutter analyze and git diff --check passed. APK 2007 built and installed. Seven phone captures inspected: Home dark/light, scrolled dark tools and large light text; More dark/light and enlarged dark text. Plan and reading routes opened on device. Independent finish review found no material UI regression but requested proof persistence. Hero and final comparisons now exist: automatic score 64.27%, below 72%; native cards are taller than the illustrative approved comp. Gate remains failed/open, no override. User informed and asked whether to refine density with another build or keep APK 2007 for inspection; awaiting decision.
