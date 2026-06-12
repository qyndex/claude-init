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
import * as fs from "node:fs";

const DATE = new Date().toISOString().slice(0, 10); // 2026-05-28
const FEATURE = process.env.VERIFY_FEATURE ?? "adhoc";
const OUT = `verify/${DATE}-${FEATURE}`;

// e2e-audit e2e-rig-1: the rig must START the app — nothing else in the chain
// provisions a server, so journeys previously ran against a dead port.
// Resolution order: E2E_SERVER_CMD env → package.json dev/start script → fail
// LOUD (a silent skip would let "evidence" be captured against nothing).
function detectServerCommand(): string {
  if (process.env.E2E_SERVER_CMD) return process.env.E2E_SERVER_CMD;
  try {
    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
    if (pkg.scripts?.dev) return "npm run dev";
    if (pkg.scripts?.start) return "npm run start";
    if (pkg.scripts?.preview) return "npm run preview";
  } catch {
    /* no package.json — fall through to the loud failure below */
  }
  throw new Error(
    "evidence rig: no server command detected — set E2E_SERVER_CMD or add a dev/start script to package.json. " +
      "Refusing to run journeys against a dead port (e2e-audit e2e-rig-1).",
  );
}

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3000";

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
  webServer: {
    command: detectServerCommand(),
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  use: {
    baseURL: BASE_URL,
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
          // ← full HTTP traces. CAVEAT (e2e-audit e2e-rig-5): a fixed path is
          // CLOBBERED per worker — with workers > 1 only the last context's HAR
          // survives. Either run evidence suites with `workers: 1`, or template
          // the path per test (e.g. `${OUT}/har/${testInfo.parallelIndex}.har`
          // via a fixture) and merge afterwards.
          recordHar: { path: `${OUT}/network.har`, content: "embed" },
        },
      },
    },
  ],
});
