# TEST token checks

Run the offline suite from the repository root:

```sh
forge build
forge test
```

All imports use the project's committed dependencies. No installation, RPC,
environment mutation, FFI, or filesystem permission is needed by the default suite.
Fuzz tests use Foundry's default run count. The stateful invariant uses the default
run count with 64 calls per sequence and fails on unexpected handler reverts.

| File | Checks |
| --- | --- |
| `TESTToken.t.sol` | Constructor metadata and full deployer supply; exact transfers; cumulative events; zero/self transfers; finite/infinite approval; failed transfers; valid ABI probes for mint, burn, ownership, admin, metadata setters and upgrades; runtime opcode inspection. |
| `TESTTokenEdgeCases.t.sol` | Approval replacement and isolation; exhausted and revoked authorization; failed operations are atomic; huge amounts and allowances; zero callers/receivers; contract recipients; malformed calldata and rejected native ETH. |
| `TESTTokenInvariant.t.sol` | Seven randomized actions interleave transfers, approvals, existing-allowance spending and rejected operations. A separate ledger checks every actor's balance, allowance and cumulative total, exact events, conserved supply and fixed metadata. |
| `LaunchIntegration.t.sol` | External distribution of 10%; a single-sided 90% TEST seed with rounding dust forwarded to the specified remainder address; economics-derived opening prices; real v4 swaps in both currency orderings; exact settlement; LP fee accounting; failed-swap rollback and subsequent trading. |
| `MainnetFork.t.sol` | Optional Ethereum mainnet transfer and event smoke test, skipped when no fork is selected. |

The pool integration constructs the committed Uniswap v4 `PoolManager` at
`0x000000000004444c5dc75cB358380D2e3dE08A90`. Its swaps, liquidity accounting,
unlock callbacks and settlement execute actual v4 code. The pool uses fee `12500`
(1.25% in v4's millionth units), tick spacing `60`, and the supplied IMD address.
Assertions compare both currency deltas to actual balance changes and verify the
swap event and accrued LP fees. A token transfer tax would break these checks.

The factory, two-leaf Merkle distributor, and IMD balance model are test harnesses,
not the deployed factory/distributor/IMD implementations. These tests establish
the token's compatibility with their launch transfers; they do not audit those
external contracts. The token itself neither distributes nor retains the swarm
allocation during construction. The launch constants used by the fixture match
the supplied brief and existing `launch.json`; the suite does not read the
manifest at runtime or change protected configuration.

To run the optional smoke test against a mainnet RPC and a pinned block where IMD
and the PoolManager exist:

```sh
forge test --match-contract MainnetForkTest \
  --fork-url "$MAINNET_RPC_URL" --fork-block-number "$MAINNET_FORK_BLOCK"
```

The live-state fork run remains outstanding in the offline verification environment.
That smoke test deploys TEST into the fork and exercises transfers and cumulative
events; live factory execution and swaps against deployed IMD are not covered by it.
