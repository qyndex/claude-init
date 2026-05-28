---
name: image-generation
description: Use when a user-facing visual asset is needed (hero, illustration, icon, OG card, badge, mock). Orchestrates reuse-first → programmatic → icon → photo → AI illustration → vector → text-in-image. Round 9 C+D.
when_to_use: User asks for "hero image", "illustration", "OG card", "icon", "logo", "mock", "image needed"; spec mentions visual assets.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# Image Generation

## Mandate

Generate or source the right visual asset with reuse-first discipline, license safety, and cost gate.

## Orchestration (top-down decision tree)

1. **REUSE CHECK** — grep `public/images/`, `public/illustrations/`, `assets/` for existing match by filename + alt-text. ALWAYS first.
2. **PROGRAMMATIC?** — OG / social / certificate / dashboard chart? → `@vercel/og` (free, sub-200ms, HTML → PNG). Save to `public/og/`.
3. **ICON?** — `lucide-react` / `@tabler/icons-react` / `@heroicons/react` — import directly, never AI-generate raster icons.
4. **PHOTO?** — Pexels MCP search first (CC0). AI photo only if no stock match.
5. **ILLUSTRATION?** — Replicate FLUX Schnell ($0.003/image, Apache-2.0). Upgrade to FLUX Pro ($0.04) only if quality fails.
6. **VECTOR / BRAND?** — Recraft V3 MCP ($0.04 raster / $0.08 SVG). Best for brand icons, scalable assets.
7. **TEXT-IN-IMAGE?** — Ideogram via Replicate route (opt-in, ~$0.04-0.11).

## Output

Save to `public/images/<slug>-<hash8>.{png,svg,webp}` and emit:
- `assets-manifest.json` entry: `{slug, source, license, alt_text, prompt, cost_cents, created_at}`
- Inline `<Image>` usage in the component with alt text in same PR
- WebP preferred at <100KB; SVG when vector available

## License + safety policy

Hard-block (via `pre-bash-guard.sh` extension):
- "in the style of <living artist>" / "<Studio Ghibli|Pixar|Disney|Marvel>"
- "photo of <real person name>"
- Non-commercial models (FLUX-dev, Stable Diffusion 2.1 non-commercial)

Allow:
- FLUX Schnell (Apache-2.0)
- FLUX Pro (commercial)
- Recraft V3 (commercial)
- Pexels (CC0)
- @vercel/og (your HTML, no third-party model)

## Cost gate

`.claude/scripts/image-budget.sh`:
- Per-image hard cap: **$0.10**
- Daily budget: **$5** default
- Log every call to `.claude/state/image-spend.jsonl`
- Alert at 80% daily, hard-stop at 100%

## Procedure (new image)

1. Reuse check (grep)
2. Pick tier (see decision tree)
3. If AI: write prompt; run license-policy check; submit to MCP
4. Cost-budget check
5. Save to `public/images/<slug>-<hash>.<ext>`
6. Update `assets-manifest.json`
7. Use `<Image>` (Next) or `<img loading="lazy">` (other) with alt text
8. Commit with `chore(assets): add <slug> via <provider>` + Conventional trailer

## Hard rules

- Reuse > generate
- Commercial-OK outputs only
- No copyrighted styles, no real people
- Alt text required (a11y)
- Cost-gated (see `image-budget.sh`)
- Provenance recorded in `assets-manifest.json`

## References

- @vercel/og: https://vercel.com/docs/og-image-generation
- Replicate FLUX: https://replicate.com/black-forest-labs/flux-schnell
- Recraft V3: https://www.recraft.ai/
- Pexels API: https://www.pexels.com/api/

## Done means

- Asset saved with documented source + license
- `<Image>` used with alt text
- `assets-manifest.json` updated
- Cost within daily budget
