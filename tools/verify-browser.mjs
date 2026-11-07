// Verifies every runnable example in a real browser.
//
// For each page with an enabled Run button: load it, click Run, wait for the
// BEAM-in-Wasm to finish, and compare the output with the output captured on
// the native BEAM at build time (which the page ships with).
//
//   node tools/verify-browser.mjs [baseUrl]     default http://localhost:8787
//
// Exit status 1 if any example fails to run in the browser, or produces
// different output (after normalising pids/refs) and isn't listed in
// tools/browser-diffs.json with a reason.

import { chromium } from "playwright";
import { readFile } from "node:fs/promises";

const base = process.argv[2] ?? "http://localhost:8787";
const CONCURRENCY = 4;
const TIMEOUT_MS = 60_000;

const allowed = JSON.parse(
  await readFile(new URL("./browser-diffs.json", import.meta.url), "utf8").catch(() => "{}"),
);

const normalize = (s) =>
  s
    .replace(/#PID<\d+\.\d+\.\d+>/g, "#PID<_>")
    .replace(/#Reference<[\d.]+>/g, "#Reference<_>")
    .replace(/#Port<[\d.]+>/g, "#Port<_>")
    .replace(/#Function<[^>]+>/g, "#Function<_>")
    .replace(/\s+$/g, "");

const sitemap = await (await fetch(`${base}/sitemap.xml`)).text();
const paths = [...sitemap.matchAll(/<loc>https:\/\/[^/]+(\/[^<]*)<\/loc>/g)]
  .map((m) => m[1])
  .filter((p) => p !== "/");

const browser = await chromium.launch();
const results = [];

async function check(path) {
  const page = await browser.newPage();
  try {
    await page.goto(base + path);
    const run = page.locator("#run");
    if ((await run.count()) === 0) return { path, status: "skipped" };

    const expected = normalize(await page.locator("#output").innerText());
    await run.click();
    await page.waitForFunction(
      () => /\[(finished|failed) in \d+ ms|\[error:/.test(document.querySelector("#output").innerText),
      null,
      { timeout: TIMEOUT_MS },
    );
    const text = await page.locator("#output").innerText();
    if (!/\[finished in \d+ ms/.test(text)) return { path, status: "failed", text };

    const actual = normalize(text.replace(/\n*\[finished in \d+ ms, in your browser\]\s*$/, ""));
    if (actual === expected) return { path, status: "ok" };
    if (allowed[path]) return { path, status: "allowed-diff", reason: allowed[path] };
    return { path, status: "diff", expected, actual };
  } catch (error) {
    return { path, status: "failed", text: String(error) };
  } finally {
    await page.close();
  }
}

const queue = [...paths];
await Promise.all(
  Array.from({ length: CONCURRENCY }, async () => {
    while (queue.length) results.push(await check(queue.shift()));
  }),
);
await browser.close();

let bad = 0;
for (const r of results.sort((a, b) => a.path.localeCompare(b.path))) {
  const mark = { ok: "✓", skipped: "-", "allowed-diff": "~" }[r.status] ?? "✗";
  console.log(`${mark} ${r.status.padEnd(12)} ${r.path}${r.reason ? `  (${r.reason})` : ""}`);
  if (r.status === "failed") {
    bad++;
    console.log(r.text.split("\n").map((l) => "    " + l).join("\n"));
  } else if (r.status === "diff") {
    bad++;
    console.log("    --- native BEAM\n" + r.expected.split("\n").map((l) => "    " + l).join("\n"));
    console.log("    +++ browser\n" + r.actual.split("\n").map((l) => "    " + l).join("\n"));
  }
}
console.log(`\n${results.filter((r) => r.status === "ok").length} ok, ${bad} problem(s)`);
process.exit(bad ? 1 : 0);
