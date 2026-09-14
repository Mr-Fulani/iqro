---
name: IQRO mobile
description: Existing emerald and gold Flutter design system for Quran reading and daily practice.
colors:
  light-primary: "#0B5D4A"
  light-on-primary: "#FFFFFF"
  light-primary-container: "#D9EEE7"
  light-on-primary-container: "#063E33"
  light-secondary: "#9A6D22"
  light-on-secondary: "#FFFFFF"
  light-background: "#F7F4EC"
  light-surface: "#FFFDF8"
  light-on-surface: "#17201D"
  light-error: "#BA1A1A"
  light-outline: "#CBC8BE"
  light-outline-variant: "#E4E0D6"
  light-ink: "#073E34"
  light-ink-soft: "#1E6657"
  light-sand: "#F5EAD5"
  light-lavender: "#ECE8F6"
  light-gold: "#C49647"
  light-panel-soft: "#EFEEE8"
  light-line: "#DCD8CE"
  dark-primary: "#91D7C3"
  dark-on-primary: "#00382C"
  dark-primary-container: "#0C5847"
  dark-on-primary-container: "#C4F4E4"
  dark-secondary: "#E7C27D"
  dark-on-secondary: "#402D00"
  dark-background: "#071A16"
  dark-surface: "#10221D"
  dark-on-surface: "#F2F2EA"
  dark-error: "#FFB4AB"
  dark-outline: "#75847E"
  dark-outline-variant: "#34473F"
  dark-ink: "#0A2B24"
  dark-ink-soft: "#17483D"
  dark-sand: "#332C21"
  dark-lavender: "#292735"
  dark-gold: "#E2B665"
  dark-panel-soft: "#172A24"
  dark-line: "#30443D"
typography:
  display-small:
    fontFamily: serif
    fontSize: 36px
    fontWeight: 600
    lineHeight: 1.1
  headline-medium:
    fontFamily: serif
    fontSize: 28px
    fontWeight: 600
    lineHeight: 1.15
  title-large:
    fontSize: 22px
    fontWeight: 700
    lineHeight: 1.25
  title-medium:
    fontSize: 17px
    fontWeight: 700
  body-large:
    fontSize: 16px
    lineHeight: 1.5
  body-medium:
    fontSize: 14px
    lineHeight: 1.45
  label-large:
    fontSize: 14px
    fontWeight: 700
  eyebrow:
    fontWeight: 800
    letterSpacing: 1.6px
rounded:
  card: 22px
  control: 16px
  list-icon: 14px
  snackbar: 14px
  dialog: 24px
  sheet-top: 28px
spacing:
  page-inline: 16px
  page-top: 8px
  page-bottom: 24px
  card-inset: 16px
  field-inset: 16px
  list-inline: 4px
  icon-gap: 12px
  eyebrow-bottom: 5px
components:
  filled-button-light:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.light-on-primary}"
    typography: "{typography.label-large}"
    rounded: "{rounded.control}"
  filled-button-dark:
    backgroundColor: "{colors.dark-primary}"
    textColor: "{colors.dark-on-primary}"
    typography: "{typography.label-large}"
    rounded: "{rounded.control}"
  outlined-button:
    typography: "{typography.label-large}"
    rounded: "{rounded.control}"
  card-light:
    backgroundColor: "{colors.light-surface}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  card-dark:
    backgroundColor: "{colors.dark-surface}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  field-light:
    backgroundColor: "{colors.light-surface}"
    rounded: "{rounded.control}"
    padding: "{spacing.field-inset}"
  field-dark:
    backgroundColor: "{colors.dark-surface}"
    rounded: "{rounded.control}"
    padding: "{spacing.field-inset}"
  navigation:
    height: 72px
  list-icon:
    rounded: "{rounded.list-icon}"
    size: 44px
---

# Design System: IQRO mobile

## Overview

IQRO's confirmed visual identity is emerald and gold. Warm neutral surfaces, deep green reading panels, and serif headings give the existing application a quiet, readable character. Rounded native controls and clear iconography support daily use.

This document records the incumbent Flutter system, rather than proposing another identity. The sources of truth are `lib/core/theme/iqro_theme.dart` and `lib/core/design_system/iqro_widgets.dart`. The implemented Home and More composition also follows `lib/features/home/home_dashboard_cards.dart`, `lib/features/home/home_screen.dart`, `lib/core/design_system/iqro_action_grid.dart`, and `lib/features/more/more_screen.dart`. Current native phone screenshots in `.impeccable/review/` cover Home and More in both themes, including larger text. The incumbent core theme remains unchanged. No separate creative metaphor has been confirmed. This is documentation of the current implementation; final visual acceptance remains pending and is not implied by the screenshot record.

**Key Characteristics:**
- Emerald and gold identity in both light and dark themes.
- Serif display and section headings paired with native Material text.
- Tonal surfaces, fine borders, and limited resting elevation.
- Native Flutter controls with directional layout and scalable text.

## Colors

The palette combines emerald, gold, warm neutrals, and supporting sand and lavender panels. Frontmatter names are documentation aliases for the actual `ColorScheme` and `IqroColors` fields; they are not new Dart tokens.

### Primary

- **Emerald / pale emerald:** `primary` serves interactive emphasis; its `onPrimary` pairing supplies content contrast. Dark mode uses a pale primary above deep green surfaces.
- **Soft emerald panel:** `primaryContainer` and `onPrimaryContainer` provide selected navigation and status surfaces.
- **Deep emerald ink:** `ink` and `inkSoft` support darker branded panels. `ink` also backgrounds snackbars; it is not the default body text color.

### Secondary

- **Gold:** `secondary` is the Material secondary role; the separate `gold` extension accents symbols and decorative details. Preserve the distinction.
- **Sand and lavender:** supporting panel colors distinguish tools. These are existing supporting colors, not replacements for the emerald/gold identity.

### Neutral

- **Cream / deep green background:** scaffold canvas; `surface` provides cards and controls.
- **On-surface:** normal readable content. Obtain secondary text through the theme's inherited Material roles where existing widgets do so.
- **Soft panel:** an alternate quiet container.
- **Line:** card borders and dividers. Material `outline` and `outlineVariant` remain separate roles.
- **Error:** retain the explicit light/dark Material error colors for error states.

**The Theme Pairing Rule.** Resolve colors from the active `ColorScheme` or `context.iqroColors`; keep each foreground paired with its intended surface.

## Typography

`displaySmall` and `headlineMedium` explicitly request the platform `serif` family. Other documented roles inherit the native Material family from `ThemeData`; no custom body font is registered in the app's pubspec. Do not promise one named typeface across devices or scripts.

The frontmatter records only explicit overrides. Inherited weight, line height, tracking, and unspecified Material roles remain Flutter defaults. Values written as `px` are portable documentation units corresponding to Flutter logical pixels; native text scaling still applies.

- **Display small:** the incumbent serif display role, retained in the shared theme; the compact Home reading card now uses `titleLarge`.
- **Headline medium:** section headings through `IqroSectionHeader`.
- **Title large / medium:** substantial UI labels and tool titles.
- **Body large / medium:** reading metadata and explanatory text.
- **Label large:** filled and outlined button labels.
- **Eyebrow:** `labelSmall` with bold, spaced uppercase styling and bottom separation; normal uses primary, light uses white at 78% opacity. It is a small contextual label, not a replacement for body text.

## Layout

The verified operating context is an Android phone. `IqroPage` wraps content in `SafeArea(bottom: false)` and normally a vertical `SingleChildScrollView`; dragging dismisses the keyboard. Default directional insets are defined in frontmatter. Root tabs use bottom clearance of 76 logical pixels, or 148 when the player is active, through `iqroRootTabPadding`.

`IqroTopBar` has a height of 64, or 72 with a subtitle. Its title and subtitle each occupy one line with ellipsis. List rows have a minimum height of 64. Buttons have a minimum size of 48 × 52, not a fixed text-clipping height.

Reuse directional start/end padding and alignment for Russian, English, Arabic, and Turkish. Cards containing translated labels must grow with content. `IqroActionGrid`, shared by Home features and More tools, builds rows at their natural content height and stretches sibling cards to the tallest card in each row. Gaps are 12 logical pixels. It uses one column below 300 logical pixels of available width or when scaled 16-point text exceeds 22; otherwise it uses two columns, or three at 720 and above. These are component-local layout thresholds, not a global tablet or desktop policy. There is no fixed card aspect ratio.

Home prayer and reading summaries stack their text and actions when their inner available width is below 280, or when scaled 16-point text exceeds 20. Other Home card titles wrap naturally; secondary feature and utility descriptions intentionally use at most two lines with ellipsis. A minimum row height never prevents growth for translated labels.

## Elevation & Depth

The core system uses tonal separation and thin borders. Cards and navigation have zero configured elevation; top bars suppress scrolled-under elevation. Cards, dialogs, and bottom sheets suppress surface tint. No reusable custom box-shadow scale is defined in these core files. Native Material components retain their inherited interaction and modal behavior.

Do not introduce a global shadow or animation system from an isolated screen effect. Native press, focus, disabled, and feedback states continue to come from Material unless a component explicitly overrides them.

## Shapes

The card radius belongs to `CardTheme` and `IqroCard`. Controls, list icon tiles, snackbars, dialogs, and top corners of sheets use their own frontmatter tokens. Preserve this distinction: the existing card radius is not a global radius for every surface.

`IqroCard` clips with `Clip.antiAlias` and uses a one logical pixel border from `line`, unless overridden. Tool panels and branded panels can intentionally use transparent borders. The IQRO logo retains its established arch artwork. The compact Home reading card no longer uses the earlier decorative reading-panel arch.

## Components

### Buttons

Filled and outlined buttons are native Material controls with strong labels and the control radius. Both use the minimum size described in Layout. Outlined buttons use the theme extension's `line` border. Text buttons retain Material defaults; there is no distinct custom ghost-button spec. Press, focus, disabled colors, and state overlays are inherited rather than hand-authored in the theme.

### Cards / Containers

`IqroCard` is the reusable bordered surface with the default card inset. It accepts color, border color, padding, and an optional tap handler. `InkWell` supplies native interaction feedback. Keep information cards noninteractive when there is no action. The themed Flutter `Card` shares the shape but supplies no default content padding itself.

### Inputs / Fields

Fields use a filled surface, control radius, and the documented inset. Both general and enabled borders use `line`. Focused, error, and disabled treatments otherwise resolve through Material; no custom glow or focus animation is defined.

### Navigation

Five destinations remain Home, Quran, Plan, Audio, and More, with localized labels and outlined/selected icon pairs. The bar has no elevation and uses the primary container indicator. The application shell uses surface at 96% opacity and places the active mini-player directly above it. Labels inherit `labelSmall` with weight 700.

### Chips

The existing `Chip` for forthcoming content uses inherited Material styling. No custom chip radius, padding, or selection palette is declared in the core theme; do not invent a second chip system.

### Section headers and list rows

`IqroSectionHeader` aligns an optional action to the bottom of a flexible heading column, optionally preceded by an eyebrow. `IqroListTile` combines a primary-container icon tile, a native title/subtitle, and an optional trailing widget or chevron. Its small horizontal inset supports placement inside a padded parent card.

### Status and async feedback

`IqroStatusBanner` uses a borderless primary-container card with a leading icon, flexible text, and an optional text action. `IqroAsyncError` centers a cloud-off icon, explanatory content, and outlined retry action. `IqroLoading` exposes a localized live-region label around an adaptive progress indicator.

### Home dashboard

The implemented composition follows the agreed Home hierarchy: prayer first, continuing reading second, and the daily plan third. The feature grid follows, then a shared utilities card and an optional guest banner. These changes compose the incumbent theme rather than replacing its palette or shapes.

- **Prayer:** `HomePrayerCard` uses `ink` with an `inkSoft` border, gold mosque/time accents, white summary text, and a reminder action. The action uses pale emerald (`dark-primary`) in both themes for contrast against the deep panel. The next prayer time uses tabular figures and explicit left-to-right numeric direction. Loading and unavailable schedules display honest placeholders. The reminder control has a 48 × 48 minimum target.
- **Continue reading:** `HomeContinueReadingCard` uses the normal surface, a primary book icon, `titleLarge` surah name, reading position, and a filled Read action. Its dark-theme button is warm white (`#FFFCF5`) with ink content; light mode keeps the standard primary button. A separated compact bookmark row has a minimum height of 48. Missing data disables reading until available; errors expose Retry.
- **Daily plan:** `HomePlanCard` is a compact surface card showing the real achieved/target amount and unit. Its progress bar is 6 logical pixels high with a local radius of 4. Labels can wrap. Completion is shown only when a loaded, non-error goal has a positive target and is achieved; loading and error states remain distinct.
- **Features:** reading after prayer, memorization, audio, and dua use `HomeFeatureCard` in the shared action grid. Each card has a 14 inset, primary icon, flexible title and short secondary text, and a chevron or active audio control. Their data and actions come from the existing app state and routes.
- **Utilities:** favorites, Hijri calendar, reminders, and downloads share a divided card. `HomeUtilityRow` uses a minimum height of 72, no content inset, and a primary icon; the parent supplies horizontal padding. Its compact bookmark variant uses 48. Calendar details and other secondary descriptions can truncate after two lines without clipping the title.

### More tools

The existing sand calendar/prayer cards, lavender memorization card, primary-container dua card, and soft-panel favorites card retain their colors and card radius. Their icon tiles are 48 square with a local radius of 15 and surface at 65% opacity. Natural-height action-grid rows accommodate the full translated tool title and forward arrow, replacing the earlier fixed-height overflow. Account rows and forthcoming-content chip retain their existing native components.

## Do's and Don'ts

### Do:
- Do preserve the IQRO emerald and gold identity in both themes.
- Do reuse the existing theme roles and native widgets before introducing local visual overrides.
- Do let translated labels wrap and containers grow with native text scaling.
- Do preserve directional layout, native feedback, and bottom clearance for the player and navigation.

### Don't:
- Don't apply the card radius globally to buttons, fields, sheets, or dialogs.
- Don't infer a custom body font, global shadow scale, or tablet breakpoint that the implementation does not define.
- Don't encode one Home composition as a system-wide rule for every screen.
- Don't restore fixed-height action-grid rows that clip translated tool titles or large text.
