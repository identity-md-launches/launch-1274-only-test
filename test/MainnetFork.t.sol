// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TESTToken} from "../src/TESTToken.sol";

/// @notice Optional mainnet transfer/event smoke test. Offline verification skips it cleanly.
contract MainnetForkTest is Test {
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;

    event TransferRunningTotal(address indexed sender, uint256 cumulativeAmount);

    function test_MainnetForkTransfersAndRunningTotals() public {
        string memory url = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        uint256 blockNumber = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (blockNumber == 0) vm.createSelectFork(url);
        else vm.createSelectFork(url, blockNumber);
        assertEq(block.chainid, 1, "fork must be Ethereum mainnet");
        assertGt(MANAGER.code.length, 0, "PoolManager must exist at fork block");
        assertGt(IMD.code.length, 0, "IMD must exist at fork block");

        TESTToken token = new TESTToken();
        address alice = makeAddr("fork alice");
        address bob = makeAddr("fork bob");
        address spender = makeAddr("fork spender");
        vm.expectEmit(true, false, false, true, address(token));
        emit TransferRunningTotal(address(this), 100e18);
        token.transfer(alice, 100e18);
        vm.expectEmit(true, false, false, true, address(token));
        emit TransferRunningTotal(alice, 25e18);
        vm.prank(alice);
        token.transfer(bob, 25e18);
        vm.prank(alice);
        token.approve(spender, 15e18);
        vm.expectEmit(true, false, false, true, address(token));
        emit TransferRunningTotal(alice, 40e18);
        vm.prank(spender);
        token.transferFrom(alice, bob, 15e18);
        assertEq(token.balanceOf(alice), 60e18);
        assertEq(token.balanceOf(bob), 40e18);
        assertEq(token.cumulativeTransferred(alice), 40e18);
        assertEq(token.cumulativeTransferred(spender), 0);
        assertEq(token.totalSupply(), 1e27);
    }
}
