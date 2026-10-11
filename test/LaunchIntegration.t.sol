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
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";

contract LaunchIntegrationTest is Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    struct SwapEventData {
        int128 amount0;
        int128 amount1;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        int24 tick;
        uint24 fee;
    }

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

    function testFuzz_PoolSettlementNeverTaxesTEST(bool tokenIsZero, uint128 rawBuy) public {
        _launchAndTrade(tokenIsZero, bound(rawBuy, 1e12, 1 ether));
    }

    function test_UnderfundedSwapsRollBackWhenTESTIsCurrency0() public {
        _checkUnderfundedSwaps(true);
    }

    function test_UnderfundedSwapsRollBackWhenTESTIsCurrency1() public {
        _checkUnderfundedSwaps(false);
    }

    function test_ZeroSwapCannotChangePoolOrTokenState() public {
        _launch(true);
        bytes32 beforeState = _accountingHash();
        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        trader.swap(key, false, 0);
        assertEq(_accountingHash(), beforeState);
        _assertSettled();
    }

    function _checkUnderfundedSwaps(bool tokenIsZero) internal {
        _launch(tokenIsZero);
        bytes32 beforeState = _accountingHash();
        // The offline IMD probe reverts with arithmetic underflow when it cannot pay.
        // With TEST as currency0, PoolManager has already sent TEST before that failure.
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        trader.swap(key, !tokenIsZero, 0.01 ether);
        assertEq(_accountingHash(), beforeState, "unfunded buy must roll back every token and pool change");
        _assertSettled();

        PairTokenProbe(IMD).mint(address(trader), 0.01 ether);
        trader.swap(key, !tokenIsZero, 0.01 ether);
        uint256 bought = token.balanceOf(address(trader));
        assertGt(bought, 0);
        beforeState = _accountingHash();
        vm.expectRevert(
            abi.encodeWithSelector(TESTToken.ERC20InsufficientBalance.selector, address(trader), bought, bought + 1)
        );
        trader.swap(key, tokenIsZero, bought + 1);
        assertEq(_accountingHash(), beforeState, "failed sell must also roll back any prior IMD payout");
        _assertSettled();

        // A failed unlock must not freeze later legitimate trading.
        trader.swap(key, tokenIsZero, bought);
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(token.cumulativeTransferred(address(trader)), bought);
        assertEq(token.totalSupply(), SUPPLY);
        _assertSettled();
    }

    function _launchAndTrade(bool tokenIsZero, uint256 buyAmount) internal {
        _launch(tokenIsZero);
        _tradeRoundTrip(tokenIsZero, buyAmount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function _launch(bool tokenIsZero) internal {
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
        _assertSettled();
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
        vm.recordLogs();
        distributor.claim(first, firstAmount, leafB);
        _assertRunningLog(vm.getRecordedLogs(), address(distributor), firstAmount);
        vm.recordLogs();
        distributor.claim(second, secondAmount, leafA);
        _assertRunningLog(vm.getRecordedLogs(), address(distributor), SWARM);
        assertEq(token.balanceOf(first), firstAmount);
        assertEq(token.balanceOf(second), secondAmount);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.cumulativeTransferred(address(distributor)), SWARM);
        assertEq(token.cumulativeTransferred(first), 0);
        assertEq(token.cumulativeTransferred(second), 0);
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
        Vm.Log[] memory buyLogs = vm.getRecordedLogs();
        _assertRunningLog(buyLogs, MANAGER, bought);
        _assertSwapLog(buyLogs, boughtDelta);
        assertEq(uint256(-int256(tokenIsZero ? boughtDelta.amount1() : boughtDelta.amount0())), buyAmount);
        assertEq(PairTokenProbe(IMD).balanceOf(MANAGER), buyAmount);
        _assertPoolFees(tokenIsZero, buyAmount, 0);
        _assertSettled();
        vm.recordLogs();
        BalanceDelta soldDelta = trader.swap(key, tokenIsZero, bought);
        assertEq(token.balanceOf(address(trader)), 0, "all bought tokens must be sellable");
        assertEq(uint256(-int256(tokenIsZero ? soldDelta.amount0() : soldDelta.amount1())), bought);
        assertEq(token.balanceOf(MANAGER), managerBefore, "sell settlement must arrive whole");
        assertEq(token.cumulativeTransferred(address(trader)), bought);
        Vm.Log[] memory sellLogs = vm.getRecordedLogs();
        _assertRunningLog(sellLogs, address(trader), bought);
        _assertSwapLog(sellLogs, soldDelta);
        uint256 returnedIMD = PairTokenProbe(IMD).balanceOf(address(trader));
        assertEq(uint256(int256(tokenIsZero ? soldDelta.amount1() : soldDelta.amount0())), returnedIMD);
        assertEq(PairTokenProbe(IMD).balanceOf(MANAGER) + returnedIMD, buyAmount);
        _assertPoolFees(tokenIsZero, buyAmount, bought);
        _assertSettled();
        // The pool charges its specified LP fee. TEST adds no transfer/swap tax.
        assertGt(PairTokenProbe(IMD).balanceOf(address(trader)), 0);
        assertLt(PairTokenProbe(IMD).balanceOf(address(trader)), buyAmount);
    }

    function _assertSwapLog(Vm.Log[] memory logs, BalanceDelta delta) internal view {
        uint256 matched;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == MANAGER && logs[i].topics.length > 0
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                assertEq(logs[i].topics.length, 3);
                assertEq(logs[i].topics[1], PoolId.unwrap(key.toId()));
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(trader)))));
                SwapEventData memory emitted = abi.decode(logs[i].data, (SwapEventData));
                assertEq(emitted.amount0, delta.amount0());
                assertEq(emitted.amount1, delta.amount1());
                assertEq(emitted.fee, 12500, "v4 fee units are millionths: 12500 is 1.25 percent");
                (uint160 price, int24 tick,,) = manager.getSlot0(key.toId());
                assertEq(emitted.sqrtPriceX96, price);
                assertEq(emitted.tick, tick);
                assertEq(emitted.liquidity, manager.getLiquidity(key.toId()));
                ++matched;
            }
        }
        assertEq(matched, 1, "must perform an actual PoolManager swap");
    }

    function _assertPoolFees(bool tokenIsZero, uint256 pairInput, uint256 testInput) internal view {
        (uint256 feeGrowth0, uint256 feeGrowth1) = manager.getFeeGrowthGlobals(key.toId());
        uint128 liquidity = manager.getLiquidity(key.toId());
        assertGt(liquidity, 0);
        uint256 pairFees = FullMath.mulDiv(tokenIsZero ? feeGrowth1 : feeGrowth0, liquidity, 1 << 128);
        uint256 testFees = FullMath.mulDiv(tokenIsZero ? feeGrowth0 : feeGrowth1, liquidity, 1 << 128);
        // The bounded round trip stays inside the sole funded range. Input includes
        // ceil(input * 12500 / 1e6) LP fees; conversion from Q128 fee growth loses <= 1 unit.
        uint256 expectedPairFees = pairInput - pairInput * 987_500 / 1_000_000;
        uint256 expectedTestFees = testInput - testInput * 987_500 / 1_000_000;
        assertApproxEqAbs(pairFees, expectedPairFees, 1, "only the specified IMD input LP fee accrues");
        assertApproxEqAbs(testFees, expectedTestFees, 1, "only the specified TEST input LP fee accrues");
        if (testInput == 0) assertEq(testFees, 0, "buy output must have no TEST fee");
    }

    function _assertSettled() internal view {
        assertFalse(manager.isUnlocked());
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(manager.currencyDelta(address(trader), key.currency0), 0);
        assertEq(manager.currencyDelta(address(trader), key.currency1), 0);
        assertEq(manager.currencyDelta(address(factory), key.currency0), 0);
        assertEq(manager.currencyDelta(address(factory), key.currency1), 0);
    }

    function _accountingHash() internal view returns (bytes32) {
        (uint160 price, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());
        (uint256 fee0, uint256 fee1) = manager.getFeeGrowthGlobals(key.toId());
        bytes32 poolState =
            keccak256(abi.encode(price, tick, protocolFee, lpFee, fee0, fee1, manager.getLiquidity(key.toId())));
        return keccak256(
            abi.encode(
                poolState,
                token.totalSupply(),
                token.balanceOf(MANAGER),
                token.balanceOf(address(trader)),
                token.cumulativeTransferred(MANAGER),
                token.cumulativeTransferred(address(trader)),
                PairTokenProbe(IMD).balanceOf(MANAGER),
                PairTokenProbe(IMD).balanceOf(address(trader))
            )
        );
    }

    function _assertRunningLog(Vm.Log[] memory logs, address sender, uint256 amount) internal view {
        uint256 matched;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(token) && logs[i].topics.length > 0
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
