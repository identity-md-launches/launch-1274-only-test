// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {TESTToken} from "../src/TESTToken.sol";

contract TransferHandler is Test {
    TESTToken public token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalances;
    mapping(address => uint256) public expectedTotals;
    mapping(address => mapping(address => uint256)) public expectedAllowances;

    constructor() {
        token = new TESTToken();
        actors = [address(this), makeAddr("invariant alice"), makeAddr("invariant bob"), makeAddr("invariant spender")];
        expectedBalances[address(this)] = 1e27;
        // Fund each actor through real transfers so early calls also exercise nonzero amounts.
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], 1e27 / 4));
            expectedBalances[address(this)] -= 1e27 / 4;
            expectedBalances[actors[i]] = 1e27 / 4;
            expectedTotals[address(this)] += 1e27 / 4;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalances[from]);
        vm.recordLogs();
        vm.prank(from);
        require(token.transfer(to, amount));
        _modelAndCheckLog(from, to, amount, vm.getRecordedLogs());
    }

    function delegatedTransfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount, bool infinite) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[3];
        uint256 amount = bound(rawAmount, 0, expectedBalances[from]);
        vm.prank(from);
        require(token.approve(spender, infinite ? type(uint256).max : amount));
        expectedAllowances[from][spender] = infinite ? type(uint256).max : amount;
        vm.recordLogs();
        vm.prank(spender);
        require(token.transferFrom(from, to, amount));
        if (!infinite) expectedAllowances[from][spender] -= amount;
        _modelAndCheckLog(from, to, amount, vm.getRecordedLogs());
        assertEq(token.allowance(from, spender), infinite ? type(uint256).max : 0);
    }

    // Separate approval and spending actions expose revocation, replacement, and stale
    // authorization across random calls instead of approving before every transferFrom.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : bound(rawAmount, 0, 2e27);
        vm.recordLogs();
        vm.prank(owner);
        require(token.approve(spender, amount));
        expectedAllowances[owner][spender] = amount;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Approval(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(owner))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(spender))));
        assertEq(abi.decode(logs[0].data, (uint256)), amount);
    }

    function spendExistingAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowances[from][spender];
        uint256 spendable = expectedBalances[from] < approved ? expectedBalances[from] : approved;
        uint256 amount = bound(rawAmount, 0, spendable);
        vm.recordLogs();
        vm.prank(spender);
        require(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) expectedAllowances[from][spender] -= amount;
        _modelAndCheckLog(from, to, amount, vm.getRecordedLogs());
    }

    function rejectedAllowance(uint256 fromSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowances[from][spender];
        // Infinite allowances cannot be exceeded. They are checked by successful spends.
        if (approved == type(uint256).max) return;
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, actors[0], approved + 1);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function rejectedZeroReceiver(uint256 fromSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowances[from][spender];
        uint256 spendable = expectedBalances[from] < approved ? expectedBalances[from] : approved;
        uint256 amount = bound(rawAmount, 0, spendable);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalances[from];
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientBalance.selector, from, held, held + 1));
        vm.prank(from);
        token.transfer(to, held + 1);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function _modelAndCheckLog(address from, address to, uint256 amount, Vm.Log[] memory logs) private {
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        expectedTotals[from] += amount;
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(from))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(to))));
        assertEq(abi.decode(logs[0].data, (uint256)), amount);
        assertEq(logs[1].emitter, address(token));
        assertEq(logs[1].topics.length, 2);
        assertEq(logs[1].topics[0], keccak256("TransferRunningTotal(address,uint256)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(from))));
        assertEq(abi.decode(logs[1].data, (uint256)), expectedTotals[from]);
    }
}

contract TESTTokenInvariantTest is StdInvariant, Test {
    TransferHandler internal handler;
    TESTToken internal token;

    function setUp() public {
        handler = new TransferHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = TransferHandler.transfer.selector;
        selectors[1] = TransferHandler.delegatedTransfer.selector;
        selectors[2] = TransferHandler.rejectedTransfer.selector;
        selectors[3] = TransferHandler.approve.selector;
        selectors[4] = TransferHandler.spendExistingAllowance.selector;
        selectors[5] = TransferHandler.rejectedAllowance.selector;
        selectors[6] = TransferHandler.rejectedZeroReceiver.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ConservationAndGrossTotalsAcrossSequences() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            sum += balance;
            assertEq(balance, handler.expectedBalances(actor));
            assertEq(token.cumulativeTransferred(actor), handler.expectedTotals(actor));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowances(actor, spender));
            }
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.name(), "Only test");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
