# Only test (TEST)

`src/TESTToken.sol` is the sole deployable project contract. Its argument-free constructor mints exactly **1,000,000,000 TEST with 18 decimals (10^27 minor units)** to `msg.sender`. Name, symbol, decimals and supply are constants. There is no owner, administrator, proxy, upgrade path, mint entry point, burn entry point, fee, transfer restriction or external contract call.

Each successful `transfer` or `transferFrom` emits the standard `Transfer` event followed by `TransferRunningTotal(address indexed sender, uint256 cumulativeAmount)`. `cumulativeTransferred(sender)` returns the sender's lifetime gross outgoing amount in minor units. For delegated transfers the sender is `from`, not the spender. Self-transfers count, zero transfers emit the unchanged total, failed transfers change nothing, and the constructor mint is excluded. Receiving tokens does not reduce the running total. Infinite allowances remain infinite; finite allowances are consumed.

The external launch factory receives the entire supply. It sends 10% through its Merkle distributor, allocates 90% to single-sided TEST/IMD liquidity, and forwards any integer-liquidity rounding remainder to the specified `remainderTo`. TESTToken neither implements nor initiates these operations. No application contracts are requested in `launch.json`.

The manifest fixes the IMD pair, fee `12500`, tick spacing `60`, opening market cap of `2500 IMD`, and the supplied provenance price. The factory derives the actual opening price using the deployed currency order. The token charges no transfer or swap tax; Uniswap's separate 1.25% pool fee still applies. Test settlement follows the [Uniswap v4 PoolManager flow](https://developers.uniswap.org/docs/protocols/v4/concepts/flash-accounting).

Build and check from the repository root:

```sh
forge build
forge test
forge fmt --check
python3 scripts/verify_delivery.py --token-only
```

Solidity is pinned to 0.8.26, Cancun, optimizer enabled, 200 runs, metadata bytecode hash disabled. Every Solidity import is vendored as an ordinary file under `lib/`; no package download, submodule, FFI or filesystem permission is required. Dependency provenance and licenses are listed in [DEPENDENCIES.md](DEPENDENCIES.md). The Python delivery check uses only the standard library.

The offline suite covers token behavior, error rollback, absence of administrative entry points, forbidden runtime opcodes, 3,000 fuzz cases, and 256 invariant sequences of 64 calls. Integration tests construct an actual Uniswap v4 PoolManager at the specified mainnet address, use a test-only IMD balance model, and run a factory/distributor/seed/buy/sell flow in both currency orders. They check exact token settlement and sender totals, the 10% allocation, 90% liquidity budget, and remainder conservation. All helper contracts live under `test/` and are not launch applications.

The optional mainnet transfer/event smoke test skips when no Foundry fork is active. Run it with `forge test --match-contract MainnetForkTest --fork-url <mainnet-rpc-url> --fork-block-number <block-number>`, supplying an Ethereum mainnet RPC URL and a block where both supplied mainnet contracts exist. Tests never read or write environment variables, and no RPC key is included. Live mainnet state was **not** tested in this delivery; the local integration does not establish the current IMD implementation or factory policy. The supplied protected suite belongs to the external verifier and is not represented as having run locally.

For a fast offline smoke check using the existing tests, run `forge test --match-contract TESTTokenTest --match-test 'test_(ConstructorMintsOnceAndRetainsNothing|RunningTotalsAccumulatePerSenderInMinorUnits|FailedTransferFromRollsBackAllowanceAndTotals)$'`. This covers deployment, full supply, exact transfers, cumulative events, and failure rollback. The token-only delivery checker validates the exact manifest and compiled ABI without requiring artwork; omit `--token-only` for the separate artwork checks.

The five 1024×1024 image-generated options are documented in [logos/README.md](logos/README.md). [artifacts/logo.png](artifacts/logo.png) is the selected minimal test-tube mark. It was inspected as a 32-pixel circle on light and dark backgrounds; each option was inspected at 64 pixels. See [REVIEW.md](REVIEW.md) for the local adversarial review and its limits.

## Website delivery

The Only test website is in **`site/`**: plain HTML, CSS and JavaScript that runs without compilation. The ready-to-publish copy is **`dist/`**. The accepted Solidity contracts, launch manifest, dependencies and Foundry configuration are unchanged by the website work.

The creator's monochrome wordmark and request for generous space guide the design. Eight sections cover the hero, story, live market data, buying guide, tokenomics, eight downloadable SVG memes, the meme generator/sticker stress test, and community sharing. See [DESIGN.md](DESIGN.md) for the implemented design system and [SITE-VALIDATION.md](SITE-VALIDATION.md) for coverage, fixes and limitations.

### Install and preview

No package install is needed to run or publish the site. From the repository root, preview the source with Python:

```sh
python3 -m http.server 8000 --directory site
```

Open `http://localhost:8000/`. To preview the exported copy, replace `site` with `dist`. Stop the foreground server with Ctrl+C. A plain file server has no `/simd-coin.json`: the interface will correctly show unavailable data and `launching…`, and the browser may report that one expected endpoint 404. Do not add a made-up contract or market-data file to make the preview look live.

### Rebuild the static export

The production packaging command uses Node.js and only its standard library (validated with Node 24.21.0). It copies the runnable source, verifies expected metadata, and rejects dependency/cache directories or unexpected runtime file types:

```sh
node scripts/build-site.mjs
```

This is a copy/export step, not a compilation requirement. Edit `site/`, then regenerate `dist/`; do not maintain two different versions. All scripts, styles, fonts and images use relative asset URLs. `/simd-coin.json` deliberately targets the same-origin root, as required by the launch service. Canonical and social metadata use the production domain.

### Typecheck and browser checks

The exact development dependencies are pinned in `web/package.json` and `web/package-lock.json`. They are not runtime dependencies and are not copied to `dist/`. Install them outside the checkout so no dependency directory or cache enters the submission:

```sh
mkdir -p /tmp/onlytest-tools
cp web/package.json web/package-lock.json /tmp/onlytest-tools/
npm ci --prefix /tmp/onlytest-tools --ignore-scripts --cache /tmp/onlytest-npm-cache
/tmp/onlytest-tools/node_modules/.bin/tsc -p web/tsconfig.json
node scripts/check-site.mjs
python3 scripts/check-site-delivery.py
```

The browser script defaults to the system Chrome executable at `/opt/google/chrome/chrome`. On another machine, set `ONLYTEST_CHROME` to an installed Chrome/Chromium executable. Set `ONLYTEST_TOOLS` if the development packages were installed somewhere else. These paths belong to the local environment and are never embedded in the site. JavaScript is checked with TypeScript's strict `checkJs` mode and JSDoc; no compiled JavaScript is generated.

The browser suite fulfills requests from the actual `dist/` files under a virtual HTTPS `/preview/` subpath. It requires no live API, registry mirror, credentials or deployed token. It creates a random **test-only** address in memory and exercises prelaunch, live, invalid and stale-data states. Its virtual clock verifies the 30-second refresh immediately. It validates all nine PNG download controls, keyboard and pointer interactions, navigation, reduced motion, text enlargement, assets and accessibility. Screenshots and its machine-readable report are saved in `web/review/`; temporary downloads/failure traces stay under `test/scratch/`.

Actual results: production export and strict JavaScript typecheck passed; **29 browser checks and four axe accessibility scans passed**, with zero reported WCAG A/AA violations. Ten widths from 320 to 1920px were checked for overflow. The supplied browser also inspected the HTTP-served export at mobile and desktop widths, including both pages. Foundry: **17 passed, 0 failed, 1 skipped**; the skipped test needs an explicitly selected mainnet fork. These are local checks, not independent certification. Axe leaves some contrast cases for manual review; native screen readers, Safari/Firefox, physical devices, native zoom and social-network card rendering were not tested.

### Publish and live data

Publish the **contents of `dist/`** at `https://onlytest.si-md.xyz/`, including `404.html` and every file in `assets/`. Use the host's static 404 handling; no SPA rewrite or application server is needed. For a nested mount, serve its exported `404.html` at that mount's URL so relative assets resolve there. The launch platform must continue to serve `/simd-coin.json` at the origin root. No production deployment or transaction was sent by this task.

The feed supplies `token`, `coinUrl`, `chartUrl`, and `market.priceUsd`, `market.marketCap`, `market.volume24h`. Nothing in the website hardcodes a TEST address. The primary link says “View launch” before deployment, then “Buy $TEST” after a valid token arrives. Missing stats stay as dashes; failed updates identify the last received data. Refreshes run every 30 seconds while visible, with an eight-second timeout and a manual retry.

A supported, loadable feed `logo` overrides the bundled wordmark in the hero, sticker and memes. If it cannot be loaded safely for PNG export, the local logo remains available. The optional `x` field can supply an X profile URL. With no profile supplied, the community link searches X for Only test/$TEST, and the three share buttons open distinct prefilled intents. This avoids inventing an official account.

The provided logo is a 96×96 WebP; it is preserved, including in the social metadata, rather than replaced with earlier logo proposals. That input limits large-image sharpness. Local font provenance and licenses are in `site/assets/CREDITS.txt` and `site/assets/fonts/`. The page has no wallet connector, trackers, cookies, data-collection form or external font request. Meme text stays in memory. Visible visuals are CSS/SVG; a temporary canvas is used only to generate downloadable 1200×1200 PNGs.
