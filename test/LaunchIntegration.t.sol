// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TESTToken} from "../src/TESTToken.sol";
import {V4Actor, PairTokenProbe, MerkleDistributorProbe} from "./helpers/LaunchHarness.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract LaunchIntegrationTest is Test {
    using StateLibrary for IPoolManager;

    uint256 internal constant SUPPLY = 1e27;
    uint256 internal constant SWARM = SUPPLY / 10;
    uint256 internal constant POOL_BUDGET = SUPPLY * 9 / 10;
    uint256 internal constant Q96 = 1 << 96;
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant REMAINDER = 0x000000000000000000000000000000000000dEaD;
    IPoolManager internal manager;
    V4Actor internal factory;
    V4Actor internal trader;
    TESTToken internal token;
    PoolKey internal key;

    function setUp() public {
        // Build in place: v4's immutable original-address guard must match the mainnet address.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool built, bytes memory runtime) = MANAGER.call("");
        require(built && runtime.length > 0);
        vm.etch(MANAGER, runtime);
        manager = IPoolManager(MANAGER);
        vm.etch(IMD, address(new PairTokenProbe()).code);
        factory = new V4Actor(manager);
        trader = new V4Actor(manager);
    }

    function test_SeedAndSwapBothWaysWhenTESTIsCurrency0() public {
        _launchAndTrade(true, 0.01 ether);
    }

    function test_SeedAndSwapBothWaysWhenTESTIsCurrency1() public {
        _launchAndTrade(false, 0.01 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_PoolSettlementNeverTaxesTEST(bool tokenIsZero, uint128 rawBuy) public {
        _launchAndTrade(tokenIsZero, bound(rawBuy, 1e12, 1 ether));
    }

    function _launchAndTrade(bool tokenIsZero, uint256 buyAmount) internal {
        _deployInOrder(tokenIsZero);
        assertEq(token.balanceOf(address(factory)), SUPPLY, "constructor must not distribute");
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.cumulativeTransferred(address(factory)), 0);
        _distributeSwarm();

        key = PoolKey(
            Currency.wrap(tokenIsZero ? address(token) : IMD),
            Currency.wrap(tokenIsZero ? IMD : address(token)),
            12500,
            60,
            IHooks(address(0))
        );
        uint160 openingPrice =
            uint160(_sqrt(FullMath.mulDiv(tokenIsZero ? 2500e18 : SUPPLY, 1 << 192, tokenIsZero ? SUPPLY : 2500e18)));
        if (tokenIsZero) assertEq(openingPrice, 125270724187523965593206900);
        int24 tick = manager.initialize(key, openingPrice);
        (uint160 currentPrice,,, uint24 fee) = manager.getSlot0(key.toId());
        assertEq(currentPrice, openingPrice);
        assertEq(fee, 12500);
        _seed(tokenIsZero, tick, openingPrice);
        _tradeRoundTrip(tokenIsZero, buyAmount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function _deployInOrder(bool tokenIsZero) internal {
        bytes32 initHash = keccak256(type(TESTToken).creationCode);
        for (uint256 salt; salt < 1000; ++salt) {
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(salt), initHash))))
            );
            if ((predicted < IMD) == tokenIsZero) {
                token = factory.deploy(bytes32(salt));
                assertEq(address(token), predicted);
                return;
            }
        }
        revert("test address search exhausted");
    }

    function _distributeSwarm() internal {
        address first = makeAddr("swarm contributor");
        address second = makeAddr("swarm seat");
        uint256 firstAmount = SWARM / 5;
        uint256 secondAmount = SWARM - firstAmount;
        bytes32 leafA = keccak256(bytes.concat(keccak256(abi.encode(first, firstAmount))));
        bytes32 leafB = keccak256(bytes.concat(keccak256(abi.encode(second, secondAmount))));
        bytes32 root =
            leafA < leafB ? keccak256(abi.encodePacked(leafA, leafB)) : keccak256(abi.encodePacked(leafB, leafA));
        MerkleDistributorProbe distributor = new MerkleDistributorProbe(token, root);
        factory.move(token, address(distributor), SWARM);
        assertEq(token.balanceOf(address(distributor)), SWARM);
        assertEq(token.balanceOf(address(factory)), POOL_BUDGET);
        assertEq(token.cumulativeTransferred(address(factory)), SWARM);
        distributor.claim(first, firstAmount, leafB);
        distributor.claim(second, secondAmount, leafA);
        assertEq(token.balanceOf(first), firstAmount);
        assertEq(token.balanceOf(second), secondAmount);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.cumulativeTransferred(address(distributor)), SWARM);
    }

    function _seed(bool tokenIsZero, int24 tick, uint160 openingPrice) internal {
        int24 lower;
        int24 upper;
        uint256 liquidity;
        if (tokenIsZero) {
            lower = (tick / 60) * 60;
            if (TickMath.getSqrtPriceAtTick(lower) < openingPrice) lower += 60;
            upper = TickMath.maxUsableTick(60);
            uint160 a = TickMath.getSqrtPriceAtTick(lower);
            uint160 b = TickMath.getSqrtPriceAtTick(upper);
            liquidity = FullMath.mulDiv(POOL_BUDGET, FullMath.mulDiv(a, b, Q96), b - a);
        } else {
            upper = (tick / 60) * 60;
            if (TickMath.getSqrtPriceAtTick(upper) > openingPrice) upper -= 60;
            lower = TickMath.minUsableTick(60);
            liquidity = FullMath.mulDiv(
                POOL_BUDGET, Q96, TickMath.getSqrtPriceAtTick(upper) - TickMath.getSqrtPriceAtTick(lower)
            );
        }
        assertGt(liquidity, 0);
        assertLe(liquidity, type(uint128).max);
        vm.recordLogs();
        BalanceDelta seeded = factory.seed(key, lower, upper, uint128(liquidity));
        uint256 taken = POOL_BUDGET - token.balanceOf(address(factory));
        assertGt(taken, 0);
        assertLe(taken, POOL_BUDGET);
        assertEq(token.balanceOf(MANAGER), taken, "seed must arrive whole");
        assertEq(PairTokenProbe(IMD).balanceOf(MANAGER), 0, "seed must be single-sided TEST");
        assertEq(tokenIsZero ? seeded.amount1() : seeded.amount0(), 0);
        assertEq(uint256(-int256(tokenIsZero ? seeded.amount0() : seeded.amount1())), taken);
        assertEq(token.cumulativeTransferred(address(factory)), SWARM + taken);
        _assertRunningLog(vm.getRecordedLogs(), address(factory), SWARM + taken);
        // v4 integer liquidity can leave minor-unit dust, which the factory forwards exactly.
        uint256 remainder = token.balanceOf(address(factory));
        assertLe(remainder, 1e6, "rounding must not materially reduce the 90 percent seed");
        factory.move(token, REMAINDER, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(REMAINDER) + token.balanceOf(MANAGER), POOL_BUDGET);
        assertEq(token.cumulativeTransferred(address(factory)), SUPPLY);
    }

    function _tradeRoundTrip(bool tokenIsZero, uint256 buyAmount) internal {
        PairTokenProbe(IMD).mint(address(trader), buyAmount);
        uint256 managerBefore = token.balanceOf(MANAGER);
        vm.recordLogs();
        BalanceDelta boughtDelta = trader.swap(key, !tokenIsZero, buyAmount);
        uint256 bought = token.balanceOf(address(trader));
        assertGt(bought, 0);
        assertEq(PairTokenProbe(IMD).balanceOf(address(trader)), 0);
        assertEq(uint256(int256(tokenIsZero ? boughtDelta.amount0() : boughtDelta.amount1())), bought);
        assertEq(managerBefore - token.balanceOf(MANAGER), bought, "buy output must arrive whole");
        assertEq(token.cumulativeTransferred(MANAGER), bought);
        _assertRunningLog(vm.getRecordedLogs(), MANAGER, bought);
        vm.recordLogs();
        BalanceDelta soldDelta = trader.swap(key, tokenIsZero, bought);
        assertEq(token.balanceOf(address(trader)), 0, "all bought tokens must be sellable");
        assertEq(uint256(-int256(tokenIsZero ? soldDelta.amount0() : soldDelta.amount1())), bought);
        assertEq(token.balanceOf(MANAGER), managerBefore, "sell settlement must arrive whole");
        assertEq(token.cumulativeTransferred(address(trader)), bought);
        _assertRunningLog(vm.getRecordedLogs(), address(trader), bought);
        // The pool charges its specified LP fee. TEST adds no transfer/swap tax.
        assertGt(PairTokenProbe(IMD).balanceOf(address(trader)), 0);
        assertLt(PairTokenProbe(IMD).balanceOf(address(trader)), buyAmount);
    }

    function _assertRunningLog(Vm.Log[] memory logs, address sender, uint256 amount) internal view {
        uint256 matched;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(token)
                    && logs[i].topics[0] == keccak256("TransferRunningTotal(address,uint256)")
            ) {
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(sender))));
                assertEq(abi.decode(logs[i].data, (uint256)), amount);
                ++matched;
            }
        }
        assertEq(matched, 1, "each token movement must emit exactly one running total");
    }

    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        result = x;
        uint256 next = (x + 1) / 2;
        while (next < result) {
            result = next;
            next = (x / next + next) / 2;
        }
    }
}
