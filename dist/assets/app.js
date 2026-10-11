// @ts-check
import { templates, memeSvg, imageData, downloadPng } from "./memes.js";
/** @template {HTMLElement} T @param {string} selector @returns {T} */
function el(selector) {
  const node = document.querySelector(selector);
  if (!node) throw new Error(`Missing interface element: ${selector}`);
  return /** @type {T} */ (node);
}
/** @param {string} message */
function notify(message) {
  el("#toast-message").textContent = message;
  el("#toast").hidden = false;
}
el("#dismiss-toast").addEventListener("click", () => {
  el("#toast").hidden = true;
});
const root = document.documentElement;
const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
let paused = reduced.matches;
function motionAllowed() {
  return !paused && !reduced.matches;
}
function syncMotion() {
  root.classList.toggle("motion-paused", paused || reduced.matches);
  const button = el(".motion-toggle");
  button.setAttribute("aria-pressed", String(paused || reduced.matches));
  button.setAttribute(
    "aria-label",
    paused || reduced.matches ? "Resume animations" : "Pause animations",
  );
  el(".motion-label").textContent =
    paused || reduced.matches ? "Motion off" : "Motion on";
  el(".motion-icon").textContent = paused || reduced.matches ? "▷" : "Ⅱ";
}
el(".motion-toggle").addEventListener("click", () => {
  if (reduced.matches) {
    notify("Motion follows your device’s reduced-motion setting.");
    return;
  }
  paused = !paused;
  syncMotion();
});
reduced.addEventListener("change", () => {
  paused = reduced.matches;
  syncMotion();
});
syncMotion();
const menu = el(".menu-toggle"),
  nav = el("#navigation");
/** @param {boolean} open @param {boolean} [restore] */
function setMenu(open, restore = false) {
  menu.setAttribute("aria-expanded", String(open));
  nav.classList.toggle("is-open", open);
  menu.innerHTML = `Menu <span aria-hidden="true">${open ? "−" : "+"}</span>`;
  if (restore) menu.focus();
}
menu.addEventListener("click", () =>
  setMenu(menu.getAttribute("aria-expanded") !== "true"),
);
nav
  .querySelectorAll("a")
  .forEach((link) => link.addEventListener("click", () => setMenu(false)));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && menu.getAttribute("aria-expanded") === "true")
    setMenu(false, true);
});
document.addEventListener("click", (event) => {
  if (
    event.target instanceof Node &&
    !nav.contains(event.target) &&
    !menu.contains(event.target)
  )
    setMenu(false);
});
window
  .matchMedia("(min-width: 861px)")
  .addEventListener("change", () => setMenu(false));
const observer =
  "IntersectionObserver" in window
    ? new IntersectionObserver(
        (entries) =>
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-revealed");
              observer?.unobserve(entry.target);
            }
          }),
        { threshold: 0.1 },
      )
    : null;
document.querySelectorAll(".reveal").forEach((node) => observer?.observe(node));
/** @param {HTMLElement} button */
function burst(button) {
  if (!motionAllowed()) return;
  const box = button.getBoundingClientRect();
  for (let i = 0; i < 22; i++) {
    const bit = document.createElement("i");
    bit.className = "confetti";
    bit.setAttribute("aria-hidden", "true");
    bit.style.left = `${box.left + box.width / 2}px`;
    bit.style.top = `${box.top + box.height / 2}px`;
    document.body.append(bit);
    const angle = Math.random() * Math.PI * 2,
      travel = 50 + Math.random() * 150;
    const animation = bit.animate(
      [
        { transform: "translate(0,0) rotate(0)", opacity: 1 },
        {
          transform: `translate(${Math.cos(angle) * travel}px,${Math.sin(angle) * travel - 70}px) rotate(${Math.random() * 600}deg)`,
          opacity: 0,
        },
      ],
      { duration: 700 + Math.random() * 300, easing: "cubic-bezier(.2,0,0,1)" },
    );
    animation.onfinish = () => bit.remove();
  }
}
document.querySelectorAll(".magnetic").forEach((node) => {
  const button = /** @type {HTMLElement} */ (node);
  button.addEventListener("pointermove", (event) => {
    if (
      !motionAllowed() ||
      event.pointerType !== "mouse" ||
      button.getAttribute("aria-disabled") === "true"
    )
      return;
    const b = button.getBoundingClientRect();
    button.style.translate = `${(event.clientX - b.left - b.width / 2) * 0.06}px ${(event.clientY - b.top - b.height / 2) * 0.12}px`;
  });
  button.addEventListener("pointerleave", () => {
    button.style.translate = "";
  });
});
/** Only web navigation from the launch feed; never executable or credential-bearing URLs. @param {unknown} value */
function safeUrl(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value, location.origin);
    return url.protocol === "https:" && !url.username && !url.password
      ? url.href
      : null;
  } catch {
    return null;
  }
}
let contract = "";
let hasLiveData = false;
let inFlight = false;
let lastUpdated = "";
const statValues = new Map();
const statFrames = new Map();
/** @param {unknown} value */
function marketNumber(value) {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (typeof value === "string" && !/^\d+(\.\d+)?$/.test(value)) return null;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
/** @param {number} value @param {string} key */
function formatMoney(value, key) {
  if (key === "priceUsd")
    return value === 0
      ? "$0"
      : value < 0.00000001
        ? "<$0.00000001"
        : new Intl.NumberFormat("en-US", {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: value < 1 ? 8 : 2,
          }).format(value);
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: value >= 1000000 ? "compact" : "standard",
    maximumFractionDigits: value >= 1000000 ? 2 : 0,
  }).format(value);
}
/** @param {string} key @param {unknown} raw */
function showStat(key, raw) {
  const node = el(`[data-stat="${key}"]`);
  const value = marketNumber(raw);
  cancelAnimationFrame(statFrames.get(key) || 0);
  if (value === null) {
    node.textContent = "—";
    statValues.delete(key);
    return;
  }
  const start = statValues.get(key) ?? value;
  statValues.set(key, value);
  if (!motionAllowed() || start === value) {
    node.textContent = formatMoney(value, key);
    return;
  }
  const began = performance.now();
  const frame = (/** @type {number} */ now) => {
    const t = Math.min(1, (now - began) / 650);
    node.textContent = formatMoney(
      start + (value - start) * (1 - (1 - t) ** 3),
      key,
    );
    if (t < 1 && motionAllowed())
      statFrames.set(key, requestAnimationFrame(frame));
    else node.textContent = formatMoney(value, key);
  };
  statFrames.set(key, requestAnimationFrame(frame));
}
/** @param {string} type @param {unknown} url @param {string} label */
function setLaunchLink(type, url, label) {
  const value = safeUrl(url);
  document.querySelectorAll(`[data-link="${type}"]`).forEach((node) => {
    const link = /** @type {HTMLAnchorElement} */ (node);
    link.innerHTML = `${label} <span aria-hidden="true">↗</span>`;
    link.setAttribute("aria-disabled", String(!value));
    if (value) {
      link.href = value;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    } else link.removeAttribute("href");
  });
}
document.querySelectorAll("[data-link]").forEach((node) => {
  const link = /** @type {HTMLAnchorElement} */ (node);
  link.addEventListener("click", (event) => {
    if (link.getAttribute("aria-disabled") === "true") {
      event.preventDefault();
      notify(
        "Launch links are not available yet. Try Refresh data in the Reality check section.",
      );
      return;
    }
    if (link.dataset.link === "buy") burst(link);
  });
  link.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !link.hasAttribute("href")) {
      event.preventDefault();
      link.click();
    }
  });
});
/** @param {string} value @param {string} success */
async function copyText(value, success) {
  try {
    await navigator.clipboard.writeText(value);
    notify(success);
  } catch {
    notify(
      "Copy is unavailable in this browser. Select and copy the text shown on the page.",
    );
  }
}
document.querySelectorAll("[data-copy-contract]").forEach((node) =>
  node.addEventListener("click", () => {
    if (contract) void copyText(contract, "Contract address copied.");
  }),
);
el("#copy-link").addEventListener(
  "click",
  () => void copyText("https://onlytest.si-md.xyz/", "Site link copied."),
);
/** @param {unknown} data */
function applyData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data))
    throw new Error("Invalid launch data");
  const coin = /** @type {Record<string,unknown>} */ (data);
  if (
    typeof coin.name !== "string" ||
    typeof coin.symbol !== "string" ||
    !("token" in coin)
  )
    throw new Error("Invalid launch data");
  contract =
    typeof coin.token === "string" &&
    /^0x[0-9a-fA-F]{40}$/.test(coin.token) &&
    !/^0x0{40}$/i.test(coin.token)
      ? coin.token
      : "";
  document.querySelectorAll("[data-token]").forEach((node) => {
    node.textContent = contract || "launching…";
  });
  document.querySelectorAll("[data-copy-contract]").forEach((node) => {
    /** @type {HTMLButtonElement} */ (node).disabled = !contract;
  });
  setLaunchLink("buy", coin.coinUrl, contract ? "Buy $TEST" : "View launch");
  setLaunchLink("chart", coin.chartUrl, "View chart");
  el("[data-launch-note]").textContent = contract
    ? "Live on Ethereum. Opens the launch coin page."
    : "Launching… the contract appears after deployment.";
  const market =
    coin.market && typeof coin.market === "object"
      ? /** @type {Record<string,unknown>} */ (coin.market)
      : {};
  ["priceUsd", "marketCap", "volume24h"].forEach((key) =>
    showStat(key, market[key]),
  );
  lastUpdated = new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date());
  const complete = ["priceUsd", "marketCap", "volume24h"].every(
    (key) => marketNumber(market[key]) !== null,
  );
  el("#data-status").textContent = complete
    ? `Updated ${lastUpdated}. Refreshes every 30 seconds.`
    : contract
      ? `Market data not available yet. Checked ${lastUpdated}; refreshes every 30 seconds.`
      : `Launch in progress. Market data will appear here. Checked ${lastUpdated}.`;
  hasLiveData = true;
  const liveLogo = safeUrl(coin.logo);
  if (liveLogo && liveLogo !== requestedLogo) void updateLogo(liveLogo);
  const social = safeUrl(coin.x);
  if (social) {
    const url = new URL(social);
    if (
      ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].includes(
        url.hostname,
      )
    ) {
      const x = /** @type {HTMLAnchorElement} */ (el("#community-x"));
      x.href = social;
      x.innerHTML = 'Join Only test on X <span aria-hidden="true">↗</span>';
    }
  }
}
async function refreshData() {
  if (inFlight) return;
  inFlight = true;
  const refresh = /** @type {HTMLButtonElement} */ (el("#refresh-data"));
  refresh.disabled = true;
  refresh.textContent = "Refreshing…";
  try {
    const response = await fetch("/simd-coin.json", {
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
      headers: { Accept: "application/json" },
    });
    if (!response.ok) throw new Error("Feed unavailable");
    applyData(await response.json());
  } catch {
    el("#data-status").textContent = hasLiveData
      ? `Update unavailable. Showing last received data from ${lastUpdated}. Try Refresh data.`
      : "Live data unavailable. The launch details will appear when connected. Try Refresh data.";
  } finally {
    inFlight = false;
    refresh.disabled = false;
    refresh.innerHTML = 'Refresh data <span aria-hidden="true">↻</span>';
  }
}
el("#refresh-data").addEventListener("click", () => void refreshData());
window.setInterval(() => {
  if (!document.hidden) void refreshData();
}, 30000);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) void refreshData();
});
const steps = [
  {
    title: "A little home for your TEST.",
    description:
      "Use an Ethereum-compatible wallet you trust. Save its recovery phrase somewhere private. This site never asks you to connect.",
    art: "◎",
  },
  {
    title: "Fuel for the experiment.",
    description:
      "Add ETH on Ethereum mainnet to your wallet. Keep some for network gas. The coin page shows the assets and route needed for a TEST swap.",
    art: "◇",
  },
  {
    title: "Check twice. Swap once.",
    description:
      "Open the coin page using the hero button. Verify the TEST contract, review the quote, price impact, pool fee and gas, then choose whether to swap in your wallet.",
    art: "⇄",
  },
];
let activeStep = 0;
/** @param {number} index */
function selectStep(index) {
  activeStep = index;
  const step = steps[index];
  el("#guide-title").textContent = step.title;
  el("#guide-description").textContent = step.description;
  el(".guide-art").textContent = step.art;
  el("#guide-count").textContent = `Step ${index + 1} of 3`;
  el("#next-step").innerHTML =
    index === 2
      ? 'Back to step 1 <span aria-hidden="true">↺</span>'
      : 'Next step <span aria-hidden="true">→</span>';
  document.querySelectorAll("[data-step]").forEach((node) => {
    const current =
      Number(/** @type {HTMLElement} */ (node).dataset.step) === index;
    node.classList.toggle("is-active", current);
    node.setAttribute("aria-pressed", String(current));
  });
}
document
  .querySelectorAll("[data-step]")
  .forEach((node) =>
    node.addEventListener("click", () =>
      selectStep(Number(/** @type {HTMLElement} */ (node).dataset.step)),
    ),
  );
el("#next-step").addEventListener("click", () =>
  selectStep((activeStep + 1) % 3),
);
const localLogo = new URL("./logo.webp", import.meta.url).href;
let logoData = localLogo;
let requestedLogo = "";
let logoVersion = 0;
/** @param {string} url */
async function updateLogo(url) {
  requestedLogo = url;
  const version = ++logoVersion;
  try {
    const data = String(await imageData(url));
    if (version !== logoVersion) return;
    logoData = data;
    document.querySelectorAll("[data-logo]").forEach((node) => {
      /** @type {HTMLImageElement} */ (node).src = data;
    });
    renderWall();
    renderPreview();
  } catch {
    if (url !== localLogo) {
      requestedLogo = "";
      void updateLogo(localLogo);
    }
  }
}
const template = /** @type {HTMLSelectElement} */ (el("#template"));
const topText = /** @type {HTMLInputElement} */ (el("#top-text"));
const bottomText = /** @type {HTMLInputElement} */ (el("#bottom-text"));
function renderPreview() {
  el("#meme-preview").innerHTML = memeSvg(
    Number(template.value),
    topText.value,
    bottomText.value,
    logoData,
    "preview",
  );
  el("#meme-preview").setAttribute(
    "aria-label",
    `Meme preview: ${topText.value} — ${bottomText.value}`,
  );
}
function renderWall() {
  const wall = el("#meme-wall");
  if (wall.childElementCount) {
    wall.querySelectorAll(".meme-art").forEach((art, index) => {
      art.innerHTML = memeSvg(
        index,
        templates[index].top,
        templates[index].bottom,
        logoData,
        `wall-${index}`,
      );
    });
    return;
  }
  templates.forEach((item, index) => {
    const article = document.createElement("article");
    article.className = "meme-card";
    article.innerHTML = `<div class="meme-art">${memeSvg(index, item.top, item.bottom, logoData, `wall-${index}`)}</div><div class="meme-caption"><h3>0${index + 1} / ${item.name}</h3><button type="button" class="meme-download" aria-label="Download ${item.name} as PNG"><span aria-hidden="true">↓</span></button></div>`;
    article
      .querySelector("button")
      ?.addEventListener("click", async (event) => {
        const button = /** @type {HTMLButtonElement} */ (event.currentTarget);
        button.disabled = true;
        try {
          await ensureLogo();
          await downloadPng(
            memeSvg(index, item.top, item.bottom, logoData, `export-${index}`),
            `only-test-${index + 1}.png`,
          );
          notify(`${item.name} PNG downloaded.`);
        } catch {
          notify("PNG download failed. Check your connection and try again.");
        } finally {
          button.disabled = false;
        }
      });
    wall.append(article);
  });
}
async function ensureLogo() {
  if (!logoData.startsWith("data:"))
    logoData = String(await imageData(localLogo));
}
template.addEventListener("change", () => {
  const item = templates[Number(template.value)];
  topText.value = item.top;
  bottomText.value = item.bottom;
  renderPreview();
});
[topText, bottomText].forEach((input) =>
  input.addEventListener("input", renderPreview),
);
el("#download-meme").addEventListener("click", async () => {
  const button = /** @type {HTMLButtonElement} */ (el("#download-meme"));
  button.disabled = true;
  el("#download-status").textContent = "Preparing your PNG…";
  try {
    await ensureLogo();
    await downloadPng(
      memeSvg(
        Number(template.value),
        topText.value,
        bottomText.value,
        logoData,
        "custom-export",
      ),
      "only-test-my-meme.png",
    );
    el("#download-status").textContent =
      "PNG downloaded. Ready for the group chat.";
  } catch {
    el("#download-status").textContent =
      "PNG download failed. Check your connection and try again.";
  } finally {
    button.disabled = false;
  }
});
renderWall();
renderPreview();
void updateLogo(localLogo);
void refreshData();
const sticker = el("#sticker"),
  zone = el("#sticker-zone");
let vibes = 0,
  dragX = 0,
  dragY = 0,
  startX = 0,
  startY = 0,
  baseX = 0,
  baseY = 0,
  moved = false,
  pointer = -1;
function pump() {
  vibes = Math.min(100, vibes + 5);
  renderVibe();
}
function renderVibe() {
  el("#vibe-count").textContent = `${vibes}%`;
  /** @type {HTMLMeterElement} */ (el("#vibe-meter")).value = vibes;
  el("#vibe-label").textContent =
    vibes === 0
      ? "Untested. A promising start."
      : vibes < 35
        ? "Test in progress. Science-ish."
        : vibes < 70
          ? "Results: extremely online."
          : vibes < 100
            ? "Peer review: the group chat approves."
            : "100% only test. Hypothesis confirmed.";
}
/** @param {number} x @param {number} y */
function moveSticker(x, y) {
  const maxX = Math.max(0, (zone.clientWidth - sticker.offsetWidth) / 2 - 12),
    maxY = Math.max(0, (zone.clientHeight - sticker.offsetHeight) / 2 - 12);
  dragX = Math.max(-maxX, Math.min(maxX, x));
  dragY = Math.max(-maxY, Math.min(maxY, y));
  sticker.style.setProperty("--drag-x", `${dragX}px`);
  sticker.style.setProperty("--drag-y", `${dragY}px`);
}
sticker.addEventListener("dragstart", (event) => event.preventDefault());
sticker.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  pointer = event.pointerId;
  startX = event.clientX;
  startY = event.clientY;
  baseX = dragX;
  baseY = dragY;
  moved = false;
  sticker.setPointerCapture(pointer);
});
sticker.addEventListener("pointermove", (event) => {
  if (event.pointerId !== pointer) return;
  const dx = event.clientX - startX,
    dy = event.clientY - startY;
  if (Math.abs(dx) + Math.abs(dy) > 5) moved = true;
  moveSticker(baseX + dx, baseY + dy);
});
sticker.addEventListener("pointerup", (event) => {
  if (event.pointerId !== pointer) return;
  sticker.releasePointerCapture(pointer);
  pointer = -1;
  if (moved) pump();
});
sticker.addEventListener("pointercancel", () => {
  pointer = -1;
  moved = false;
});
sticker.addEventListener("click", () => {
  if (!moved) pump();
  moved = false;
});
sticker.addEventListener("keydown", (event) => {
  const offsets = /** @type {Record<string,[number,number]>} */ ({
    ArrowLeft: [-12, 0],
    ArrowRight: [12, 0],
    ArrowUp: [0, -12],
    ArrowDown: [0, 12],
  });
  const offset = offsets[event.key];
  if (offset) {
    event.preventDefault();
    moveSticker(dragX + offset[0], dragY + offset[1]);
  }
  if (event.key === "Home") {
    event.preventDefault();
    moveSticker(0, 0);
  }
});
el("#reset-vibe").addEventListener("click", () => {
  vibes = 0;
  moveSticker(0, 0);
  renderVibe();
});
window.addEventListener("resize", () => moveSticker(dragX, dragY));
