All dependencies are test-only and vendored as ordinary source files. TESTToken has no imports. Repository metadata, package managers, upstream tests, submodules and compiler binaries are not included.

| Directory | Upstream revision | Included files | License |
| --- | --- | --- | --- |
| `lib/forge-std` | [foundry-rs/forge-std v1.9.7, 77041d2ce690e692d6e03cc812b57d1ddaa4d505](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | `src/` | MIT / Apache-2.0; accompanying license files |
| `lib/v4-core` | [Uniswap/v4-core, 46c6834698c48bc4a463a86d8420f4eb1d7f3b75](https://github.com/Uniswap/v4-core/tree/46c6834698c48bc4a463a86d8420f4eb1d7f3b75) | `src/`, excluding upstream test helpers | Per-file SPDX identifiers and accompanying license |
| `lib/solmate` | [transmissions11/solmate, 4b47a19038b798b4a33d9749d25e570443520647](https://github.com/transmissions11/solmate/tree/4b47a19038b798b4a33d9749d25e570443520647) | `src/auth/Owned.sol`, required by the test PoolManager | AGPL-3.0 repository license; `Owned.sol` is AGPL-3.0-only |

The upstream PoolManager's ownership belongs to the test protocol implementation, not TESTToken. Only `TESTToken` is in the launch manifest; the token has no ownership powers.
