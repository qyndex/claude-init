// Journey-evidence helper — Round 10 B. Copy to e2e/_evidence.ts.
//
// Provides:
//   - test.shot(ac, label)  → AC-named screenshot, attached to the report
//   - recordApi(page, ac)   → dumps request/response pairs to verify/<date>/traces/<ac>-api.json
//
// Pattern: each test is tagged with its AC id ({ tag: ['@AC-1'] }) so spec-match.sh
// can prove every spec acceptance criterion has a passing test.

import { test as base, expect, type Page } from "@playwright/test";
import * as fs from "fs";

const DATE = new Date().toISOString().slice(0, 10);
const OUT = `verify/${DATE}-${process.env.VERIFY_FEATURE ?? "adhoc"}`;

export const test = base.extend<{
  shot: (ac: string, label: string) => Promise<void>;
}>({
  shot: async ({ page }, use, testInfo) => {
    await use(async (ac, label) => {
      const dir = `${OUT}/screenshots`;
      fs.mkdirSync(dir, { recursive: true });
      const file = `${dir}/${ac}__${label}.png`; // AC-1__after-login.png
      await page.screenshot({ path: file, fullPage: true });
      await testInfo.attach(`${ac} ${label}`, {
        path: file,
        contentType: "image/png",
      });
    });
  },
});

// Capture API request/response pairs for the journey (human-readable triage alongside HAR)
export function recordApi(page: Page, ac: string) {
  const log: unknown[] = [];
  page.on("response", async (r) => {
    const req = r.request();
    if (req.url().includes("/api/")) {
      log.push({
        ac,
        method: req.method(),
        url: req.url(),
        status: r.status(),
        reqBody: req.postData() ?? null,
        resBody: await r.text().catch(() => "<binary>"),
      });
    }
  });
  return () => {
    const dir = `${OUT}/traces`;
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(`${dir}/${ac}-api.json`, JSON.stringify(log, null, 2));
  };
}

export { expect };

// ─── Example test (copy to e2e/<spec-id>/story-1.spec.ts) ───────────────
//
// import { test, expect, recordApi } from "../_evidence";
//
// test("AC-1 user logs in and sees dashboard",
//   { tag: ["@AC-1", "@spec-042"] },   // UNPADDED AC-N — matches the spec template (e2e-audit e2e-rig-3)
//   async ({ page, shot }) => {
//     const flush = recordApi(page, "AC-1");
//     await page.goto("/login");
//     await shot("AC-1", "login-page");
//     await page.getByLabel("Email").fill("e2e@test.dev");
//     await page.getByLabel("Password").fill("correct-horse");
//     await page.getByRole("button", { name: "Sign in" }).click();
//     await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
//     await shot("AC-1", "dashboard");
//     flush();
//   });
