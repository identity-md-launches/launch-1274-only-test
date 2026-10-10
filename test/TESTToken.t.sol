// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TESTToken} from "../src/TESTToken.sol";

contract TESTTokenTest is Test {
    TESTToken internal token;
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TransferRunningTotal(address indexed sender, uint256 cumulativeAmount);

    function setUp() public {
        token = new TESTToken();
    }

    function test_ConstructorMintsOnceAndRetainsNothing() public {
        vm.recordLogs();
        TESTToken fresh = new TESTToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(fresh.name(), "Only test");
        assertEq(fresh.symbol(), "TEST");
        assertEq(fresh.decimals(), 18);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
        assertEq(fresh.balanceOf(address(fresh)), 0);
        assertEq(fresh.balanceOf(address(0)), 0);
        assertEq(fresh.cumulativeTransferred(address(this)), 0);
        assertEq(logs.length, 1, "mint must not count as an outgoing transfer");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_RunningTotalsAccumulatePerSenderInMinorUnits() public {
        _expectTransfer(address(this), alice, 12e18 + 7, 12e18 + 7);
        token.transfer(alice, 12e18 + 7);
        _expectTransfer(address(this), bob, 5e18 + 9, 17e18 + 16);
        token.transfer(bob, 5e18 + 9);
        _expectTransfer(alice, bob, 2e18 + 1, 2e18 + 1);
        vm.prank(alice);
        token.transfer(bob, 2e18 + 1);
        assertEq(token.balanceOf(alice), 10e18 + 6);
        assertEq(token.balanceOf(bob), 7e18 + 10);
        assertEq(token.cumulativeTransferred(address(this)), 17e18 + 16);
        assertEq(token.cumulativeTransferred(alice), 2e18 + 1);
        assertEq(token.cumulativeTransferred(bob), 0);
    }

    function test_TransferFromCountsHolderAndSpendsExactAllowance() public {
        token.transfer(alice, 100e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, 30e18);
        vm.prank(alice);
        token.approve(spender, 30e18);
        _expectTransfer(alice, bob, 20e18, 20e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 20e18));
        _expectTransfer(alice, bob, 10e18, 30e18);
        vm.prank(spender);
        token.transferFrom(alice, bob, 10e18);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 70e18);
        assertEq(token.balanceOf(bob), 30e18);
        assertEq(token.cumulativeTransferred(spender), 0);
    }

    function test_InfiniteAllowanceAndRevocation() public {
        token.transfer(alice, 10e18);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(alice, bob, 1e18);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        vm.prank(alice);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.cumulativeTransferred(alice), 1e18);
    }

    function test_ZeroAndSelfTransfersEmitAndDoNotChangeSupply() public {
        _expectTransfer(alice, bob, 0, 0);
        vm.prank(alice);
        token.transfer(bob, 0);
        _expectTransfer(address(this), address(this), SUPPLY, SUPPLY);
        token.transfer(address(this), SUPPLY);
        _expectTransfer(address(this), address(this), SUPPLY, SUPPLY * 2);
        token.transfer(address(this), SUPPLY);
        _expectTransfer(address(this), bob, 0, SUPPLY * 2);
        token.transfer(bob, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromToSelfStillSpendsAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 10);
        _expectTransfer(alice, alice, 10, 10);
        vm.prank(spender);
        token.transferFrom(alice, alice, 10);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_FailedTransferFromRollsBackAllowanceAndTotals() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.cumulativeTransferred(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 1);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.cumulativeTransferred(alice), 0);
    }

    function test_ZeroAddressCannotBurnOrApprove() public {
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintTransferCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TESTToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.cumulativeTransferred(address(this)), 0);
    }

    function test_NoAdministrativeEntryPointsForDeployerOrStranger() public {
        string[24] memory signatures = [
            "owner()",
            "admin()",
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "setFee(uint256)",
            "setTax(uint256)",
            "setPool(address)",
            "setTransfersEnabled(bool)",
            "grantRole(bytes32,address)",
            "setBlacklist(address,bool)"
        ];
        token.transfer(alice, 100);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, uint256(100));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(bob);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(TESTToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100), "holder must remain able to transfer");
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeHasNoDestructiveOrDelegatingOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLt(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xff && op != 0xf4 && op != 0xf2, "forbidden opcode");
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferRoundTripConservesSupplyAndGrossTotals(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        _expectTransfer(address(this), alice, amount, amount);
        token.transfer(alice, amount);
        _expectTransfer(alice, address(this), amount, amount);
        vm.prank(alice);
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.cumulativeTransferred(address(this)), amount);
        assertEq(token.cumulativeTransferred(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DelegatedTransfersAreExact(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, amount);
        _expectTransfer(alice, bob, amount, amount);
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), balance);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.cumulativeTransferred(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectTransfer(address from, address to, uint256 amount, uint256 cumulative) internal {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(from, to, amount);
        vm.expectEmit(true, false, false, true, address(token));
        emit TransferRunningTotal(from, cumulative);
    }
}
