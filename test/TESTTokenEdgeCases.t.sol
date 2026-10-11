// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TESTToken} from "src/TESTToken.sol";

/// @dev An ERC-20 recipient does not need to accept a callback or native ETH.
contract RejectingTokenRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

contract TESTTokenEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1e27;
    TESTToken internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");

    function setUp() public {
        token = new TESTToken();
    }

    function test_ApprovalReplacementIsIsolatedAndDoesNotCountAsATransfer() public {
        token.transfer(alice, 100);
        vm.startPrank(alice);
        token.approve(spender, 80);
        token.approve(bob, 7);
        vm.recordLogs();
        assertTrue(token.approve(spender, 20));
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "approval must not emit a running transfer total");
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Approval(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(spender))));
        assertEq(abi.decode(logs[0].data, (uint256)), 20);
        assertEq(token.allowance(alice, spender), 20, "replacement, not addition");
        assertEq(token.allowance(alice, bob), 7);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.cumulativeTransferred(alice), 0);
        assertEq(token.cumulativeTransferred(address(this)), 100);
    }

    function test_FiniteAllowanceCannotBeReplayedAndHolderNeedsApprovalForTransferFrom() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        vm.prank(alice);
        token.approve(spender, 30);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 30));
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 70);
        assertEq(token.balanceOf(bob), 30);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.cumulativeTransferred(alice), 30);
        assertEq(token.cumulativeTransferred(spender), 0);
    }

    function test_ZeroDelegatedTransferWithoutAllowanceEmitsUnchangedSenderTotal() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.transfer(bob, 10);
        vm.recordLogs();
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(bob))));
        assertEq(abi.decode(logs[0].data, (uint256)), 0);
        assertEq(logs[1].emitter, address(token));
        assertEq(logs[1].topics.length, 2);
        assertEq(logs[1].topics[0], keccak256("TransferRunningTotal(address,uint256)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[1].data, (uint256)), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.cumulativeTransferred(spender), 0);
    }

    function testFuzz_InsufficientBalanceIsAtomic(uint256 rawBalance, uint256 rawAmount, bool delegated, bool infinite)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        token.transfer(alice, balance);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approved);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientBalance.selector, alice, balance, amount));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(alice, bob, amount);
        } else {
            vm.prank(alice);
            token.transfer(bob, amount);
        }
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.cumulativeTransferred(alice), 0);
        assertEq(token.cumulativeTransferred(address(this)), balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceCannotSpendFundedBalance(
        uint256 rawBalance,
        uint256 rawApproved,
        uint256 rawAmount
    ) public {
        uint256 balance = bound(rawBalance, 1, SUPPLY);
        uint256 approved = bound(rawApproved, 0, balance - 1);
        uint256 amount = bound(rawAmount, approved + 1, balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.cumulativeTransferred(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FiniteAllowanceAboveSupplyStillDecrements(uint256 rawApproved) public {
        uint256 approved = bound(rawApproved, SUPPLY + 1, type(uint256).max - 1);
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), approved - SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.cumulativeTransferred(alice), SUPPLY);
        assertEq(token.cumulativeTransferred(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSenderAndApproverRevertEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(bob, 0);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.cumulativeTransferred(address(0)), 0);
    }

    function test_InvalidReceiverRollsBackFiniteAndInfiniteAllowance() public {
        token.transfer(alice, 10);
        uint256[2] memory approvals = [uint256(10), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            token.approve(spender, approvals[i]);
            vm.recordLogs();
            vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(alice, address(0), 10);
            assertEq(vm.getRecordedLogs().length, 0);
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 10);
            assertEq(token.cumulativeTransferred(alice), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_OneHoldersApprovalCannotAuthorizeSpendingAnotherHoldersTokens() public {
        token.transfer(alice, 10);
        vm.prank(bob);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(bob, spender), type(uint256).max);
    }

    function test_ContractRecipientReceivesWholeAmountWithoutCallback() public {
        RejectingTokenRecipient recipient = new RejectingTokenRecipient();
        assertTrue(token.transfer(address(recipient), SUPPLY));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.cumulativeTransferred(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MalformedCallsAndNativeValueCannotChangeState() public {
        bytes4[3] memory selectors = [token.transfer.selector, token.approve.selector, token.transferFrom.selector];
        for (uint256 i; i < selectors.length; ++i) {
            (bool ok,) = address(token).call(abi.encodePacked(selectors[i]));
            assertFalse(ok, "truncated arguments must revert");
        }
        (bool emptyOk,) = address(token).call("");
        assertFalse(emptyOk, "no fallback");
        vm.deal(address(this), 1);
        (bool valueOk,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (bob, 1)));
        assertFalse(valueOk, "token functions do not accept ETH");
        (bool receiveOk,) = address(token).call{value: 1}("");
        assertFalse(receiveOk, "no payable receive");
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.cumulativeTransferred(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
