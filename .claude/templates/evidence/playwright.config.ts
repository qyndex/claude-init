// Evidence-capture rig — Round 10 B. Copy to repo root as playwright.config.ts.
//
// Turns on the four evidence artifacts the operator needs:
//   video (full journey), trace.zip (DOM+network+console per step),
//   HAR (full HTTP traces), screenshot-on-failure.
// All routed to verify/<date>-<feature>/ so collect-evidence.sh can bundle them.
//
// Set VERIFY_FEATURE (the spec slug) before running:
//   VERIFY_FEATURE=042-checkout npx playwright test e2e/042

import { defineConfig, devices } from "@playwright/test";

const DATE = new Date().toISOString().slice(0, 10); // 2026-05-28
const FEATURE = process.env.VERIFY_FEATURE ?? "adhoc";
const OUT = `verify/${DATE}-${FEATURE}`;

export default defineConfig({
  testDir: "e2e",
  outputDir: `${OUT}/test-results`, // per-test traces, videos land here
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  reporter: [
    ["list"],
    ["html", { outputFolder: `${OUT}/html-report`, open: "never" }],
    ["json", { outputFile: `${OUT}/results.json` }], // machine-readable for spec-match.sh
    ["junit", { outputFile: `${OUT}/junit.xml` }],
  ],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3000",
    screenshot: "only-on-failure", // explicit per-AC shots come from _evidence.ts
    video: "on", // ← full journey video, every test
    trace: "on", // ← DOM+network+console, openable at trace.playwright.dev
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        contextOptions: {
          recordHar: { path: `${OUT}/network.har`, content: "embed" }, // ← full HTTP traces
        },
      },
    },
  ],
});
