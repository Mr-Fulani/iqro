# IQRO mobile UX prototype

Interactive product prototype for the future IQRO Flutter application. It remains isolated from the current web application and is not a released mobile client. It can run locally or be published as a private product preview; the bundled adapter keeps the experience usable without a backend connection.

## Run locally

Requirements: Node.js 22.13 or newer.

```bash
cd prototypes/iqro-mobile
npm ci
npm run dev
```

Open `http://localhost:3000`.

Useful deterministic QA URLs:

- `/?reset=1&screen=home&locale=ru&theme=light`
- `/?reset=1&screen=quran&locale=en&theme=light`
- `/?reset=1&screen=reader&locale=ar&theme=light`
- `/?reset=1&screen=player&locale=ru&theme=dark`

`reset=1` starts from mock defaults. Without it, choices and progress persist in `localStorage` so cross-screen scenarios can be tested.

## Validate

```bash
npm run check
```

The prototype is intentionally isolated under `prototypes/iqro-mobile`. Its mock adapter shape follows the current backend contracts, while a future Flutter client should replace this adapter with authenticated API, database, outbox, audio cache, and notification implementations.

## Product documentation

- [Mobile UX specification](./MOBILE_UX_SPEC.md)
- [Mobile design system](./MOBILE_DESIGN_SYSTEM.md)
- [Prototype report and handoff](./MOBILE_PROTOTYPE_REPORT.md)

## Content integrity

The Arabic Al-Fatiha sample comes from the repository's bundled Madani Hafs dataset. The dua sample comes from the bundled Hisn al-Muslim dataset. No religious translation is invented: translation and tafsir regions are represented as explicit product states until approved editions are connected.
