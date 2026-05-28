---
name: typography
description: Use when setting fonts, type scale, headings, body text, or measure. Enforces typographic hierarchy, readable measure, self-hosted fonts, semantic heading levels. Round 9 C.
when_to_use: User asks about fonts, headings, body text, readability, type, typography; new layout or component with text; font config edits.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Typography

## Mandate

Typography is the load-bearing element of UI design. Get it right and everything else looks better.

## Decisions encoded

### Type scale

Use a modular scale defined in `tokens.ts`:
```ts
// Perfect fourth (1.250) — versatile, slightly tight
fontSize: {
  xs:   '0.8rem',    // 12.8px
  sm:   '1rem',      // 16px  — base
  base: '1.25rem',   // 20px
  lg:   '1.563rem',  // 25px
  xl:   '1.953rem',  // 31.25px
  '2xl': '2.441rem', // 39px
  '3xl': '3.052rem', // 49px
}
```
(Or perfect fifth 1.333 for more drama.)

### Body

- **16px minimum.** 18px preferred for marketing/editorial.
- **Line-height 1.5+** for body; 1.2-1.3 for headings.
- **Max measure 75ch** — `max-w-prose` in Tailwind. Anything over 80 characters per line is hard to read.

### Hierarchy

- **One `<h1>` per page.** Use semantic levels; don't skip.
- **`<main>`, `<nav>`, `<article>`, `<aside>`** landmarks required.
- **Heading levels follow document outline**, not visual size.

### Font stack

Two families max:
1. **Sans-serif body**: Inter / Manrope / Geist / Söhne. Distinctive enough to feel intentional, neutral enough to read.
2. **Monospace**: JetBrains Mono / Fira Code / Geist Mono. For code, data, technical UI.

For DISPLAY (h1/h2/hero): use a second sans with more personality, OR a serif (Fraunces, Source Serif), OR a custom display face.

NEVER three families. NEVER Comic Sans, Times New Roman, or system defaults that scream "didn't decide."

### Self-hosting

Use `@fontsource/inter` (and similar) packages. Import in app entry:
```ts
import '@fontsource-variable/inter';
```

**Never** link to Google Fonts CDN:
- GDPR liability (Google logs IP)
- Performance (DNS lookup, CDN connection)
- Privacy

## Hard rules

- 16px min body
- One `<h1>` per page
- `max-w-prose` (or 75ch) on every text block
- Self-hosted fonts only
- Two font families max
- Heading levels never skip (h1 → h3 wrong; h1 → h2 → h3 right)

## Common pitfalls

1. **Choosing fonts in CSS instead of `tokens.ts`** — drift across the app
2. **Skipping h2 (h1 → h3)** — a11y fail
3. **Body text below 16px** — accessibility issue
4. **Letter-spacing tweaks per heading** — should be in the type scale, not ad-hoc
5. **Fixed pixel sizes** — use rem so user preferences scale

## References

- Practical Typography: https://practicaltypography.com/
- type-scale.com: https://type-scale.com/ (visual tool)
- Variable Font Inter: https://rsms.me/inter/

## Done means

- Type scale defined in `tokens.ts`
- Body ≥ 16px / line-height ≥ 1.5
- Heading hierarchy correct
- Fonts self-hosted
- `max-w-prose` on text blocks
