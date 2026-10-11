// @ts-check
/** Original SVG compositions. Canvas is used only by the PNG export function. */
export const templates = [
  { name: "The original test", top: "NOTHING TO PROVE", bottom: "ONLY TEST." },
  {
    name: "Certified overthinker",
    top: "I DID THE RESEARCH",
    bottom: "IT SAYS ONLY TEST.",
  },
  {
    name: "This is fine",
    top: "IS THIS WORKING?",
    bottom: "ONLY ONE WAY TO TEST.",
  },
  {
    name: "Very important research",
    top: "PEER REVIEWED BY",
    bottom: "THE GROUP CHAT.",
  },
  {
    name: "The group chat",
    top: "ONE NORMAL MESSAGE",
    bottom: "THE CHAT, FIVE MINUTES LATER.",
  },
  {
    name: "No thoughts",
    top: "THOUGHTS NOT FOUND",
    bottom: "ONLY TEST FOUND.",
  },
  {
    name: "Testing, testing",
    top: "TESTING. TESTING.",
    bottom: "IS THIS MEME ON?",
  },
  {
    name: "One more test",
    top: "JUST ONE MORE TEST",
    bottom: "ME, 47 TESTS AGO.",
  },
];
/** @param {string} value */
function xml(value) {
  return value.replace(
    /[&<>"']/g,
    (char) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&apos;",
      })[char] || char,
  );
}
/** @param {string} text @param {number} y @param {string} color */
function caption(text, y, color) {
  const words = Array.from(text.trim()).slice(0, 48).join("").split(/\s+/);
  /** @type {string[]} */ const lines = [];
  let line = "";
  for (const word of words) {
    if ((line + " " + word).trim().length > 24 && line) {
      lines.push(line);
      line = "";
    }
    if (word.length > 24) {
      if (line) lines.push(line);
      lines.push(word.slice(0, 24));
      line = word.slice(24);
    } else line = (line + " " + word).trim();
  }
  if (line) lines.push(line);
  const shown = lines.slice(0, 3);
  const longest = Math.max(
    1,
    ...shown.map((value) => Array.from(value).length),
  );
  const size = Math.min(
    shown.length > 2 ? 26 : 30,
    Math.floor(540 / (longest * 1.02)),
  );
  return `<text x="300" y="${y}" text-anchor="middle" fill="${color}" font-family="Arial, sans-serif" font-size="${size}" font-weight="900">${shown.map((v, i) => `<tspan x="300" dy="${i ? size + 4 : 0}">${xml(v)}</tspan>`).join("")}</text>`;
}
/** @param {number} index @param {string} top @param {string} bottom @param {string} logo @param {string} [id] */
export function memeSvg(index, top, bottom, logo, id = "meme") {
  const n = Math.max(0, Math.min(7, Math.trunc(index) || 0));
  const safeId = id.replace(/[^a-z0-9-]/gi, "");
  const paper = n === 1 || n === 4 || n === 7;
  const bg = paper ? "#f2f1ed" : "#0b0b0b";
  const ink = paper ? "#0b0b0b" : "#f2f1ed";
  /** @param {number} x @param {number} y @param {number} size @param {number} [angle] */
  const mark = (x, y, size, angle = 0) =>
    `<g transform="rotate(${angle} ${x + size / 2} ${y + size / 2})"><rect x="${x - 4}" y="${y - 4}" width="${size + 8}" height="${size + 8}" fill="#0b0b0b" stroke="#b3b3af"/><image href="${xml(logo)}" x="${x}" y="${y}" width="${size}" height="${size}" preserveAspectRatio="xMidYMid slice"/></g>`;
  const art = [
    `<circle cx="300" cy="300" r="153" fill="none" stroke="#80807b"/><circle cx="300" cy="300" r="133" fill="none" stroke="#80807b" stroke-dasharray="2 9"/><ellipse cx="300" cy="300" rx="225" ry="65" fill="none" stroke="#f2f1ed" transform="rotate(-27 300 300)"/>${mark(210, 210, 180, -8)}<text x="112" y="245" fill="#f2f1ed" font-size="68">✳</text><circle cx="491" cy="214" r="7" fill="#f2f1ed"/>`,
    `<g transform="rotate(-8 300 300)"><rect x="140" y="149" width="320" height="295" fill="#fff" stroke="#0b0b0b" stroke-width="3"/><text x="160" y="180" font-family="monospace" font-size="15">OFFICIAL UNOFFICIAL FINDINGS</text><path d="M160 193h280" stroke="#0b0b0b"/>${mark(240, 213, 120)}<text x="300" y="374" fill="#0b0b0b" text-anchor="middle" font-size="26" font-weight="900">TEST PASSED*</text><text x="300" y="405" text-anchor="middle" font-family="monospace" font-size="15">*vibes only. no science.</text></g>`,
    `<rect x="72" y="153" width="456" height="288" rx="8" fill="#141414" stroke="#b3b3af" stroke-width="3"/><path d="M72 190h456" stroke="#80807b"/><text x="95" y="178" fill="#b3b3af" font-family="monospace" font-size="17">onlytest.exe</text><text x="477" y="179" fill="#f2f1ed" font-size="23">×</text>${mark(132, 232, 120)}<text x="286" y="274" fill="#f2f1ed" font-size="25" font-weight="900">TASK FAILED</text><text x="286" y="309" fill="#f2f1ed" font-family="monospace" font-size="15">successfully.</text><rect x="287" y="342" width="130" height="43" fill="#f2f1ed"/><text x="352" y="369" fill="#0b0b0b" text-anchor="middle" font-family="monospace" font-size="16">TEST AGAIN</text>`,
    `<rect x="70" y="142" width="460" height="313" fill="url(#${safeId}-grid)" stroke="#80807b"/><path d="M300 143v312M70 300h460" stroke="#b3b3af" stroke-dasharray="5 8"/><circle cx="300" cy="300" r="130" fill="none" stroke="#f2f1ed"/>${mark(236, 236, 128)}<path d="M145 161v278M136 161h18M136 439h18" stroke="#f2f1ed"/><text x="383" y="428" fill="#b3b3af" font-family="monospace" font-size="15">SPECIMEN: TEST</text>`,
    `<rect x="50" y="149" width="286" height="78" rx="25" fill="#0b0b0b"/><text x="79" y="197" fill="#f2f1ed" font-size="28">guys. only test.</text><rect x="198" y="248" width="349" height="80" rx="25" fill="#d7d7d2" stroke="#0b0b0b" stroke-width="2"/><text x="227" y="297" fill="#0b0b0b" font-size="28">say less.</text>${mark(74, 268, 114, -9)}${mark(232, 346, 95, 7)}${mark(353, 342, 95, -5)}${mark(463, 354, 75, 12)}`,
    `<text x="300" y="305" text-anchor="middle" fill="#f2f1ed" font-family="Arial,sans-serif" font-size="170" font-weight="900" letter-spacing="-14">404</text><text x="300" y="340" text-anchor="middle" fill="#b3b3af" font-family="monospace" font-size="17">brain.exe has left the chat</text>${mark(250, 364, 100, -4)}`,
    `${[65, 98, 132, 166].map((r) => `<circle cx="300" cy="300" r="${r}" fill="none" stroke="#80807b" stroke-width="2"/>`).join("")}<path d="M80 300h440M300 140v320" stroke="#f2f1ed" stroke-dasharray="5 9"/>${mark(228, 228, 144, 8)}<rect x="430" y="162" width="91" height="35" fill="#f2f1ed"/><text x="475" y="186" text-anchor="middle" fill="#0b0b0b" font-family="monospace" font-size="15">ON AIR</text>`,
    `${mark(74, 170, 117, -9)}${mark(244, 170, 117, 4)}${mark(410, 176, 117, -5)}${mark(75, 330, 117, 7)}${mark(242, 335, 117, -7)}${mark(410, 332, 117, 12)}<text x="305" y="324" fill="#0b0b0b" text-anchor="middle" font-family="monospace" font-size="17">REPEAT UNTIL INTERNET.</text>`,
  ][n];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600" role="img" aria-label="${xml(top + " — " + bottom)}"><defs><pattern id="${safeId}-grid" width="24" height="24" patternUnits="userSpaceOnUse"><path d="M24 0H0V24" fill="none" stroke="#424240" stroke-width=".6"/></pattern></defs><rect width="600" height="600" fill="${bg}"/>${caption(top, 49, ink)}${art}${caption(bottom, 514, ink)}<text x="24" y="583" fill="${ink}" font-family="monospace" font-size="11">ONLY TEST / $TEST</text><text x="576" y="583" fill="${ink}" text-anchor="end" font-family="monospace" font-size="11">SPECIMEN 0${n + 1}</text></svg>`;
}
/** @param {string} url */
export async function imageData(url) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(8000),
    credentials: "omit",
  });
  if (!response.ok) throw new Error("Logo unavailable");
  const blob = await response.blob();
  if (
    !/^image\/(png|jpeg|webp|gif|avif)$/.test(blob.type) ||
    blob.size > 5 * 1024 * 1024
  )
    throw new Error("Unsupported logo");
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("Logo unreadable"));
    reader.readAsDataURL(blob);
  });
}
/** @param {string} svg @param {string} filename */
export async function downloadPng(svg, filename) {
  // Only an in-memory export surface; the visible page is HTML/CSS/SVG.
  const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const canvas = document.createElement("canvas");
    canvas.width = 1200;
    canvas.height = 1200;
    const context = canvas.getContext("2d");
    if (!context)
      throw new Error("PNG export is not supported in this browser.");
    context.drawImage(img, 0, 0, 1200, 1200);
    const png = await new Promise((resolve, reject) =>
      canvas.toBlob(
        (value) =>
          value ? resolve(value) : reject(new Error("PNG export failed.")),
        "image/png",
      ),
    );
    const downloadUrl = URL.createObjectURL(png);
    const link = document.createElement("a");
    link.href = downloadUrl;
    link.download = filename;
    document.body.append(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 60000);
  } finally {
    URL.revokeObjectURL(url);
  }
}
