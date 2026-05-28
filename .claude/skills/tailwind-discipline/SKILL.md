---
name: tailwind-discipline
description: Use when writing Tailwind utility classes. Enforces utility-first discipline, semantic token usage, no inline style, prettier-plugin-tailwindcss class order. Round 9 C.
when_to_use: Any .tsx/.jsx/.vue file with className; tailwind.config.* edits; new component creation; user mentions Tailwind, utility classes, CSS classes.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Tailwind Discipline

## Mandate

95%+ Tailwind utilities. No custom CSS without 3+ reuse justification. Arbitrary values require justification comment.

## Rules

- **No `!important`.** Ever. If you need it, your specificity is wrong.
- **No inline `style=`** — except dynamic values (computed transforms, animations from JS state).
- **No arbitrary values without comment.** `text-[17px]` → either add `17px` to the type scale OR add `// reason: precise alignment with logo`.
- **Extract to `@layer components`** only after 3+ uses. Name semantically: `btn-primary`, NOT `blue-button`.
- **`tailwind.config.ts`: extend, never override defaults.** Use `theme.extend.colors`, not `theme.colors`.
- **Semantic tokens, not literals.** `bg-surface-1`, NOT `bg-gray-900`. Defined in `tokens.ts` / `theme.extend`.
- **Class order via prettier-plugin-tailwindcss.** Enforce in `.prettierrc`. PR fails if classes out of order.
- **Mobile-first.** Start without prefix; add `sm:`/`md:`/`lg:` for larger. Never write `lg:px-4 px-2` — flip to `px-2 lg:px-4`.

## Anti-patterns (auto-fix)

- `style={{ color: '#000' }}` → semantic token class
- `text-[14px] leading-[20px]` → type-scale class
- `bg-[#1a1a1a]` → `bg-surface-2` (or add to tokens first)
- `mt-[13px]` → snap to scale (mt-3=12px or mt-4=16px); add 13px to scale only if it genuinely matters

## Dark mode

Use `class` strategy in `tailwind.config.ts`:
```ts
darkMode: 'class',
```
Apply to `<html>` via ThemeProvider. Tokens get dark variants via `dark:` prefix or CSS variables.

## When breaking the rules is OK

- Animations with computed values: `style={{ transform: \`rotate(\${angle}deg)\` }}`
- Iframe sizing forced by parent
- Email templates (limited CSS support → inline OK)

Each exception requires a one-line `// reason:` comment.

## Done means

- Zero `!important`
- Zero inline `style=` except dynamic
- Class order normalized via prettier
- All colors via semantic tokens
- Dark mode works on every component
