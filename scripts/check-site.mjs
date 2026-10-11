#!/usr/bin/env node
// Bounded, offline browser verification. Test dependencies live outside the submission.
import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { randomBytes } from "node:crypto";
const root = fileURLToPath(new URL("../", import.meta.url));
const toolDir = process.env.ONLYTEST_TOOLS || "/tmp/onlytest-tools";
const require = createRequire(path.join(toolDir, "package.json"));
const { chromium, expect } = require("@playwright/test");
const axe = await readFile(require.resolve("axe-core/axe.min.js"), "utf8");
const artifacts = path.join(root, "web/review");
await mkdir(artifacts, { recursive: true });
const scratch = path.join(root, "test/scratch/site-checks");
await mkdir(scratch, { recursive: true });
const contentTypes = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".webp": "image/webp",
  ".woff2": "font/woff2",
  ".svg": "image/svg+xml",
  ".txt": "text/plain",
};
const pending = {
  name: "Only test",
  symbol: "TEST",
  token: null,
  chainName: "Ethereum",
  status: "building",
  coinUrl: null,
  chartUrl: null,
  market: null,
};
const fixtureToken = "0x" + randomBytes(20).toString("hex"); // Test-only; never written to site or export.
let responseData = pending,
  requests = 0,
  feedStatus = 200;
const assetRequests = [];
const origin = "https://onlytest-check.invalid";
const url = origin + "/preview/";
const browser = await chromium.launch({
  executablePath: process.env.ONLYTEST_CHROME || "/opt/google/chrome/chrome",
  headless: true,
  args: ["--no-sandbox"],
});
const context = await browser.newContext({
  viewport: { width: 1440, height: 1000 },
  permissions: ["clipboard-read", "clipboard-write"],
  reducedMotion: "reduce",
});
// Serve the committed export through request interception: no DNS, network or registry required.
await context.route("**/*", async (route) => {
  try {
    const requestUrl = new URL(route.request().url());
    if (requestUrl.origin !== origin) {
      await route.fulfill({
        status: 200,
        contentType: "text/plain",
        body: "External navigation intercepted by test",
      });
      return;
    }
    if (requestUrl.pathname === "/simd-coin.json") {
      requests++;
      await route.fulfill({
        status: feedStatus,
        contentType: "application/json",
        body: JSON.stringify(responseData),
      });
      return;
    }
    if (!requestUrl.pathname.startsWith("/preview/")) {
      await route.fulfill({ status: 404, body: "Not found" });
      return;
    }
    assetRequests.push(requestUrl.href);
    let relative = decodeURIComponent(
      requestUrl.pathname.slice("/preview/".length),
    );
    if (!relative || relative.endsWith("/")) relative += "index.html";
    const file = path.resolve(root, "dist", relative);
    if (!file.startsWith(path.join(root, "dist") + path.sep))
      throw new Error("outside export");
    await route.fulfill({
      status: 200,
      contentType:
        contentTypes[path.extname(file)] || "application/octet-stream",
      body: await readFile(file),
    });
  } catch {
    await route.fulfill({ status: 404, body: "Not found" });
  }
});
const page = await context.newPage();
await page.clock.install();
const errors = [],
  failedResources = [],
  checks = [],
  audits = [];
page.on("pageerror", (error) => errors.push(error.message));
page.on("requestfailed", (request) => failedResources.push(request.url()));
const pass = (name, details = {}) => {
  checks.push({ name, ...details });
  console.log(`PASS: ${name}`);
};
try {
  await page.goto(url);
  await page.waitForFunction(() =>
    document
      .querySelector("#data-status")
      .textContent.includes("Launch in progress"),
  );
  await page.evaluate(() => document.fonts.ready);
  await expect(page.locator("[data-token]").first()).toHaveText("launching…");
  await expect(page.locator("[data-copy-contract]").first()).toBeDisabled();
  await expect(page.locator('[data-link="buy"]')).not.toHaveAttribute("href");
  await expect(page.locator('[data-stat="priceUsd"]')).toHaveText("—");
  assert.equal(await page.locator("main>section").count(), 8);
  assert.equal(await page.locator(".meme-card").count(), 8);
  pass(
    "Eight sections and eight SVG memes; honest prelaunch contract and unavailable data",
  );
  for (const width of [320, 360, 375, 390, 600, 768, 860, 1024, 1440, 1920]) {
    await page.setViewportSize({ width, height: width < 600 ? 844 : 1000 });
    await page.evaluate(() => window.scrollTo(0, 0));
    const sizes = await page.evaluate(() => ({
      width: innerWidth,
      scroll: document.documentElement.scrollWidth,
      body: document.body.scrollWidth,
      buy: document.querySelector('[data-link="buy"]').getBoundingClientRect()
        .bottom,
      images: [...document.images].every(
        (i) => i.complete && i.naturalWidth > 0,
      ),
    }));
    assert.ok(
      sizes.scroll <= width + 1,
      `${width}px document overflow: ${JSON.stringify(sizes)}`,
    );
    assert.ok(sizes.body <= width + 1, `${width}px body overflow`);
    assert.ok(sizes.images, "Broken images");
    if (width === 390) {
      assert.ok(sizes.buy < 844);
      await page.screenshot({
        path: path.join(artifacts, "site-mobile-390.jpg"),
        type: "jpeg",
        quality: 78,
      });
    }
    if (width === 1440)
      await page.screenshot({
        path: path.join(artifacts, "site-desktop-1440.jpg"),
        type: "jpeg",
        quality: 78,
        fullPage: true,
      });
    pass(`Home layout at ${width}px`, { buyBottom: sizes.buy });
  }
  // Real anchor targets, no unnamed controls, no broken local assets.
  const anchors = await page
    .locator('a[href^="#"]')
    .evaluateAll((nodes) => nodes.map((a) => a.getAttribute("href")));
  for (const href of anchors)
    if (href !== "#")
      assert.equal(
        await page.locator(href).count(),
        1,
        `Missing anchor ${href}`,
      );
  const loaded = await page.evaluate(() =>
    [...document.fonts]
      .filter((f) => f.status === "loaded")
      .map((f) => f.family),
  );
  assert.equal(loaded.length, 3);
  pass("All in-page links resolve, all three local fonts load");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.keyboard.press("Tab");
  await expect(page.locator(".skip-link")).toBeFocused();
  await page.keyboard.press("Enter");
  await page.locator(".menu-toggle").click();
  await expect(page.locator("#navigation")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(".menu-toggle")).toBeFocused();
  await expect(page.locator(".menu-toggle")).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  await page.locator(".menu-toggle").click();
  await page.locator('#navigation a[href="#how-to-buy"]').click();
  await expect(page.locator(".menu-toggle")).toHaveAttribute(
    "aria-expanded",
    "false",
  );
  await page.locator('[data-step="1"]').click();
  await expect(page.locator("#guide-title")).toHaveText(
    "Fuel for the experiment.",
  );
  await page.locator("#next-step").click();
  await expect(page.locator('[data-step="2"]')).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await page.locator("#next-step").click();
  await expect(page.locator('[data-step="0"]')).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  pass(
    "Keyboard skip link, mobile menu close/focus return, guide selection and all three steps",
  );
  // Inject live data only in this offline test fixture, then verify exact navigation and address copying.
  responseData = {
    ...pending,
    token: fixtureToken,
    status: "live",
    coinUrl: "https://www.si-md.xyz/launchpad/?fixture=onlytest",
    chartUrl: "https://www.si-md.xyz/launchpad/?fixture=onlytest-chart",
    market: { priceUsd: 0.000025, marketCap: 25000, volume24h: 1234.56 },
  };
  await page.locator("#refresh-data").click();
  await expect(page.locator("[data-token]").first()).toHaveText(fixtureToken);
  await expect(page.locator('[data-link="buy"]')).toHaveAttribute(
    "href",
    responseData.coinUrl,
  );
  await expect(page.locator('[data-link="chart"]')).toHaveAttribute(
    "href",
    responseData.chartUrl,
  );
  await expect(page.locator('[data-stat="priceUsd"]')).toHaveText("$0.000025");
  await expect(page.locator('[data-stat="marketCap"]')).toHaveText("$25,000");
  await page.locator("[data-copy-contract]").first().click();
  assert.equal(
    await page.evaluate(() => navigator.clipboard.readText()),
    fixtureToken,
  );
  await page.locator("#dismiss-toast").click();
  await page.locator("#copy-link").click();
  assert.equal(
    await page.evaluate(() => navigator.clipboard.readText()),
    "https://onlytest.si-md.xyz/",
  );
  await page.locator("#dismiss-toast").click();
  const shares = await page
    .locator("[data-share]")
    .evaluateAll((links) => links.map((a) => a.href));
  assert.equal(new Set(shares).size, 3);
  for (const href of shares) {
    const link = new URL(href);
    assert.equal(link.hostname, "x.com");
    assert.equal(link.pathname, "/intent/tweet");
    assert.equal(link.searchParams.get("url"), "https://onlytest.si-md.xyz/");
  }
  pass(
    "Live feed, exact buy/chart URLs, full contract copy, site-link copy and three distinct X intents",
  );
  // Advance only browser timers, no real-time wait.
  const beforePoll = requests;
  responseData = {
    ...responseData,
    market: { priceUsd: 0.000035, marketCap: 35000, volume24h: 2000 },
  };
  await page.clock.fastForward(30000);
  await expect(page.locator('[data-stat="marketCap"]')).toHaveText("$35,000");
  assert.ok(requests > beforePoll);
  await page.clock.resume();
  pass("30-second refresh verified with a virtual browser clock");
  // Check the motion-enabled update and popup without visiting an external service.
  await page.emulateMedia({ reducedMotion: "no-preference" });
  const replacementLogo = origin + "/preview/assets/logo.webp?from=live-feed";
  responseData = {
    ...responseData,
    logo: replacementLogo,
    market: { priceUsd: 0.000045, marketCap: 45000, volume24h: 2300 },
  };
  await page.locator("#refresh-data").click();
  await expect(page.locator('[data-stat="marketCap"]')).toHaveText("$45,000");
  await expect.poll(() => assetRequests.includes(replacementLogo)).toBe(true);
  const popupWaiting = page.waitForEvent("popup");
  await page.locator('[data-link="buy"]').click();
  assert.ok((await page.locator(".confetti").count()) > 0);
  const popup = await popupWaiting;
  await popup.waitForLoadState();
  assert.equal(popup.url(), responseData.coinUrl);
  await popup.close();
  await page.bringToFront();
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(page.locator(".confetti")).toHaveCount(0);
  pass(
    "Buy navigation and confetti, animated stat updates, and live-logo priority",
  );
  responseData = {
    ...pending,
    token: "not-an-address",
    coinUrl: "javascript:alert(1)",
    chartUrl: "data:text/html,unsafe",
    market: { priceUsd: -1, marketCap: "not a number", volume24h: null },
  };
  await page.locator("#refresh-data").click();
  await expect(page.locator("[data-token]").first()).toHaveText("launching…");
  await expect(page.locator('[data-link="buy"]')).not.toHaveAttribute("href");
  await expect(page.locator('[data-stat="marketCap"]')).toHaveText("—");
  responseData = { invalid: true };
  await page.locator("#refresh-data").click();
  await expect(page.locator("#data-status")).toContainText(
    "Update unavailable",
  );
  responseData = pending;
  await page.locator("#refresh-data").click();
  await expect(page.locator("#data-status")).toContainText(
    "Launch in progress",
  );
  pass(
    "Malformed feed, missing fields, invalid address, unsafe URLs, invalid numbers and recovery",
  );
  // Every PNG download must be a non-empty 1200x1200 PNG.
  async function verifyDownload(trigger, expectedName) {
    const waiting = page.waitForEvent("download");
    await trigger();
    const download = await waiting;
    assert.equal(download.suggestedFilename(), expectedName);
    const file = await download.path();
    const bytes = await readFile(file);
    assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(bytes.readUInt32BE(16), 1200);
    assert.equal(bytes.readUInt32BE(20), 1200);
    assert.ok(bytes.length > 10000);
    return bytes;
  }
  for (let i = 0; i < 8; i++) {
    await verifyDownload(
      () => page.locator(".meme-download").nth(i).click(),
      `only-test-${i + 1}.png`,
    );
    if (await page.locator("#toast").isVisible())
      await page.locator("#dismiss-toast").click();
  }
  await page.locator("#template").selectOption("3");
  await page
    .locator("#top-text")
    .fill('<script>alert("TEST")</script> & quotes');
  await page
    .locator("#bottom-text")
    .fill("ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUV");
  assert.equal(await page.locator("#meme-preview script").count(), 0);
  await verifyDownload(
    () => page.locator("#download-meme").click(),
    "only-test-my-meme.png",
  );
  await expect(page.locator("#download-status")).toContainText(
    "PNG downloaded",
  );
  await page.locator("#top-text").fill("NOTHING TO PROVE");
  await page.locator("#bottom-text").fill("ONLY TEST.");
  const png = await verifyDownload(
    () => page.locator("#download-meme").click(),
    "only-test-my-meme.png",
  );
  await writeFile(path.join(scratch, "meme-export.png"), png);
  pass(
    "All eight wall downloads and custom meme PNG export; long captions and markup remain plain text",
  );
  await page.locator("#sticker").scrollIntoViewIfNeeded();
  await page.locator("#sticker").focus();
  await page.keyboard.press("ArrowRight");
  let drag = await page
    .locator("#sticker")
    .evaluate((n) => n.style.getPropertyValue("--drag-x"));
  assert.equal(drag, "12px");
  await page.keyboard.press("Enter");
  await expect(page.locator("#vibe-count")).toHaveText("5%");
  const stickerBox = await page.locator("#sticker").boundingBox();
  await page.mouse.move(
    stickerBox.x + stickerBox.width / 2,
    stickerBox.y + stickerBox.height / 2,
  );
  await page.mouse.down();
  await page.mouse.move(
    stickerBox.x + stickerBox.width / 2 + 40,
    stickerBox.y + stickerBox.height / 2 + 25,
    { steps: 5 },
  );
  await page.mouse.up();
  await expect(page.locator("#vibe-count")).toHaveText("10%");
  for (let i = 0; i < 20; i++) await page.locator("#sticker").press("Enter");
  await expect(page.locator("#vibe-count")).toHaveText("100%");
  await page.locator("#reset-vibe").click();
  await expect(page.locator("#vibe-count")).toHaveText("0%");
  pass(
    "Pointer drag, keyboard sticker movement, click meter, 100% cap and reset",
  );
  const running = await page.evaluate(
    () =>
      document.getAnimations().filter((a) => a.playState === "running").length,
  );
  assert.equal(running, 0);
  pass("Reduced-motion setting disables all running animations");
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await expect(page.locator(".motion-toggle")).toHaveAttribute(
    "aria-pressed",
    "false",
  );
  await page.locator(".motion-toggle").click();
  assert.equal(
    await page.evaluate(
      () =>
        document.getAnimations().filter((a) => a.playState === "running")
          .length,
    ),
    0,
  );
  await page.locator(".motion-toggle").click();
  assert.ok(
    await page.evaluate(() =>
      document.getAnimations().some((a) => a.playState === "running"),
    ),
  );
  pass("Visible pause control stops and resumes continuous animation");
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const width of [375, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.addScriptTag({ content: axe });
    const audit = await page.evaluate(async () =>
      window.axe.run(document, {
        runOnly: {
          type: "tag",
          values: ["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"],
        },
      }),
    );
    audits.push({
      page: "index.html",
      width,
      violations: audit.violations.map((v) => ({
        id: v.id,
        impact: v.impact,
        description: v.description,
        nodes: v.nodes.map((n) => n.target),
      })),
      passes: audit.passes.length,
      incomplete: audit.incomplete.map((v) => v.id),
    });
    assert.deepEqual(
      audit.violations.map((v) => ({
        id: v.id,
        nodes: v.nodes.map((n) => n.target),
      })),
      [],
    );
    pass(`Home axe WCAG A/AA scan at ${width}px`);
  }
  const contrast = await page.evaluate(() => {
    const luminance = (color) => {
      const [r, g, b] = color
        .match(/[\d.]+/g)
        .slice(0, 3)
        .map(Number)
        .map((value) => {
          const v = value / 255;
          return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
        });
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    return [
      ["body", "body"],
      [".hero-description", "body"],
      [".primary", ".primary"],
      [".stat .muted", ".stats-section"],
      [".generator-controls input", ".generator-controls input"],
    ].map(([text, surface]) => {
      const foreground = getComputedStyle(document.querySelector(text)).color;
      const background = getComputedStyle(
        document.querySelector(surface),
      ).backgroundColor;
      const a = luminance(foreground),
        b = luminance(background);
      return {
        text,
        surface,
        foreground,
        background,
        ratio: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05),
      };
    });
  });
  contrast.forEach((pair) => assert.ok(pair.ratio >= 4.5));
  pass("Five rendered text/surface contrast pairs exceed 4.5:1", { contrast });
  // Text enlargement is separate from native browser zoom.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addStyleTag({ content: "html{font-size:200%}" });
  const enlarged = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    width: innerWidth,
  }));
  assert.ok(
    enlarged.scroll <= enlarged.width + 1,
    `200% text resize overflow ${JSON.stringify(enlarged)}`,
  );
  pass("200% text enlargement reflow at 390px");
  await page.goto(url + "404.html");
  await page.evaluate(() => document.fonts.ready);
  for (const width of [375, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    assert.ok(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
    );
    assert.equal(
      await page
        .locator("img")
        .evaluateAll((images) =>
          images.every((i) => i.complete && i.naturalWidth),
        ),
      true,
    );
    await page.addScriptTag({ content: axe });
    const audit = await page.evaluate(async () =>
      window.axe.run(document, {
        runOnly: {
          type: "tag",
          values: ["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"],
        },
      }),
    );
    audits.push({
      page: "404.html",
      width,
      violations: audit.violations.map((v) => ({
        id: v.id,
        impact: v.impact,
        nodes: v.nodes.map((n) => n.target),
      })),
      passes: audit.passes.length,
      incomplete: audit.incomplete.map((v) => v.id),
    });
    assert.equal(audit.violations.length, 0);
    pass(`404 page and axe scan at ${width}px`);
  }
  await page.screenshot({
    path: path.join(artifacts, "site-404.jpg"),
    type: "jpeg",
    quality: 78,
  });
  await page.locator("main a").click();
  await expect(page).toHaveURL(url);
  pass("404 home navigation works from the static subpath");
  assert.deepEqual(errors, []);
  assert.deepEqual(failedResources, []);
  pass(
    "No JavaScript exceptions or failed resource requests during successful-state checks",
  );
  const result = {
    date: new Date().toISOString(),
    checks,
    audits,
    errors,
    failedResources,
    limitations: [
      "Headless Chromium only; no physical device or screen-reader session.",
      "200% text enlargement is not native browser zoom.",
      "Local feed fixtures verify behavior; they do not establish deployed market values.",
      "Share intent destinations are verified without posting to X.",
    ],
  };
  await writeFile(
    path.join(artifacts, "site-checks.json"),
    JSON.stringify(result, null, 2) + "\n",
  );
  console.log(
    `PASS: ${checks.length} browser checks; ${audits.length} accessibility scans. Evidence in web/review/.`,
  );
} catch (error) {
  await page.screenshot({
    path: path.join(scratch, "failure.png"),
    fullPage: true,
  });
  await writeFile(
    path.join(scratch, "failed-checks.json"),
    JSON.stringify(
      { checks, audits, errors, failedResources, error: String(error) },
      null,
      2,
    ),
  );
  throw error;
} finally {
  await browser.close();
}
