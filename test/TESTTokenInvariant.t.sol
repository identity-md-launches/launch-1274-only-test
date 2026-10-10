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

    constructor() {
        token = new TESTToken();
        actors = [address(this), makeAddr("invariant alice"), makeAddr("invariant bob"), makeAddr("invariant spender")];
        expectedBalances[address(this)] = 1e27;
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
        vm.recordLogs();
        vm.prank(spender);
        require(token.transferFrom(from, to, amount));
        _modelAndCheckLog(from, to, amount, vm.getRecordedLogs());
        assertEq(token.allowance(from, spender), infinite ? type(uint256).max : 0);
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalances[from];
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientBalance.selector, from, held, held + 1));
        vm.prank(from);
        token.transfer(to, held + 1);
    }

    function _modelAndCheckLog(address from, address to, uint256 amount, Vm.Log[] memory logs) private {
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        expectedTotals[from] += amount;
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(from))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(to))));
        assertEq(abi.decode(logs[0].data, (uint256)), amount);
        assertEq(logs[1].emitter, address(token));
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
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TransferHandler.transfer.selector;
        selectors[1] = TransferHandler.delegatedTransfer.selector;
        selectors[2] = TransferHandler.rejectedTransfer.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
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
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
