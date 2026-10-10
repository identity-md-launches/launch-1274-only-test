# Only test (TEST)

`src/TESTToken.sol` is the sole deployable project contract. Its argument-free constructor mints exactly **1,000,000,000 TEST with 18 decimals (10^27 minor units)** to `msg.sender`. Name, symbol, decimals and supply are constants. There is no owner, administrator, proxy, upgrade path, mint entry point, burn entry point, fee, transfer restriction or external contract call.

Each successful `transfer` or `transferFrom` emits the standard `Transfer` event followed by `TransferRunningTotal(address indexed sender, uint256 cumulativeAmount)`. `cumulativeTransferred(sender)` returns the sender's lifetime gross outgoing amount in minor units. For delegated transfers the sender is `from`, not the spender. Self-transfers count, zero transfers emit the unchanged total, failed transfers change nothing, and the constructor mint is excluded. Receiving tokens does not reduce the running total. Infinite allowances remain infinite; finite allowances are consumed.

The external launch factory receives the entire supply. It sends 10% through its Merkle distributor, allocates 90% to single-sided TEST/IMD liquidity, and forwards any integer-liquidity rounding remainder to the specified `remainderTo`. TESTToken neither implements nor initiates these operations. No application contracts are requested in `launch.json`.

The manifest fixes the IMD pair, fee `12500`, tick spacing `60`, opening market cap of `2500 IMD`, and the supplied provenance price. The factory derives the actual opening price using the deployed currency order. The token charges no transfer or swap tax; Uniswap's separate 1.25% pool fee still applies. Test settlement follows the [Uniswap v4 PoolManager flow](https://developers.uniswap.org/docs/protocols/v4/concepts/flash-accounting).

Build and check from the repository root:

```sh
forge build
forge test
python3 scripts/verify_delivery.py
```

Solidity is pinned to 0.8.26, Cancun, optimizer enabled, 200 runs, metadata bytecode hash disabled. Every Solidity import is vendored as an ordinary file under `lib/`; no package download, submodule, FFI or filesystem permission is required. Dependency provenance and licenses are listed in [DEPENDENCIES.md](DEPENDENCIES.md). The Python delivery check uses only the standard library.

The offline suite covers token behavior, error rollback, absence of administrative entry points, forbidden runtime opcodes, 3,000 fuzz cases, and 256 invariant sequences of 64 calls. Integration tests construct an actual Uniswap v4 PoolManager at the specified mainnet address, use a test-only IMD balance model, and run a factory/distributor/seed/buy/sell flow in both currency orders. They check exact token settlement and sender totals, the 10% allocation, 90% liquidity budget, and remainder conservation. All helper contracts live under `test/` and are not launch applications.

The optional mainnet transfer/event smoke test skips when `MAINNET_RPC_URL` is absent. To run it, set that environment variable outside this repository and optionally set `MAINNET_FORK_BLOCK` to a block where both supplied mainnet contracts exist, then run `forge test --match-contract MainnetForkTest`. No RPC key is included. Live mainnet state was **not** tested in this delivery; the local integration does not establish the current IMD implementation or factory policy. The supplied protected suite belongs to the external verifier and is not represented as having run locally.

The five 1024×1024 image-generated options are documented in [logos/README.md](logos/README.md). [artifacts/logo.png](artifacts/logo.png) is the selected minimal test-tube mark. It was inspected as a 32-pixel circle on light and dark backgrounds; each option was inspected at 64 pixels. See [REVIEW.md](REVIEW.md) for the local adversarial review and its limits.
