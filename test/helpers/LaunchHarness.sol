// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TESTToken} from "../../src/TESTToken.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

interface ITransferToken {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Test-only factory/trader. No harness contract is a launch application.
contract V4Actor is IUnlockCallback {
    IPoolManager internal immutable manager;
    address internal immutable controller = msg.sender;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    modifier onlyController() {
        require(msg.sender == controller, "test controller only");
        _;
    }

    function deploy(bytes32 salt) external onlyController returns (TESTToken) {
        return new TESTToken{salt: salt}();
    }

    function move(TESTToken token, address to, uint256 amount) external onlyController {
        require(token.transfer(to, amount));
    }

    function seed(PoolKey memory key, int24 lower, int24 upper, uint128 liquidity)
        external
        onlyController
        returns (BalanceDelta)
    {
        return abi.decode(manager.unlock(abi.encode(true, abi.encode(key, lower, upper, liquidity))), (BalanceDelta));
    }

    function swap(PoolKey memory key, bool zeroForOne, uint256 amount) external onlyController returns (BalanceDelta) {
        require(amount <= uint256(type(int256).max));
        return abi.decode(manager.unlock(abi.encode(false, abi.encode(key, zeroForOne, amount))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (bool isSeed, bytes memory payload) = abi.decode(data, (bool, bytes));
        PoolKey memory key;
        BalanceDelta delta;
        if (isSeed) {
            int24 lower;
            int24 upper;
            uint128 liquidity;
            (key, lower, upper, liquidity) = abi.decode(payload, (PoolKey, int24, int24, uint128));
            (delta,) = manager.modifyLiquidity(
                key, ModifyLiquidityParams(lower, upper, int256(uint256(liquidity)), bytes32(0)), ""
            );
        } else {
            bool zeroForOne;
            uint256 amount;
            (key, zeroForOne, amount) = abi.decode(payload, (PoolKey, bool, uint256));
            delta = manager.swap(
                key,
                SwapParams(
                    zeroForOne, -int256(amount), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                ),
                ""
            );
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            uint256 owed = uint256(-int256(delta));
            manager.sync(currency);
            require(ITransferToken(Currency.unwrap(currency)).transfer(address(manager), owed));
            require(manager.settle() == owed, "settlement arrived short");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(int256(delta)));
        }
    }
}

/// @dev Test-only IMD balance model: v4 needs balanceOf and exact transfer settlement.
contract PairTokenProbe {
    string public constant symbol = "IMD";
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Test-only two-leaf Merkle distributor; the real factory supplies its own distributor.
contract MerkleDistributorProbe {
    TESTToken public immutable token;
    bytes32 public immutable root;
    mapping(bytes32 => bool) public claimed;

    constructor(TESTToken token_, bytes32 root_) {
        token = token_;
        root = root_;
    }

    function claim(address recipient, uint256 amount, bytes32 sibling) external {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(recipient, amount))));
        bytes32 computed =
            leaf < sibling ? keccak256(abi.encodePacked(leaf, sibling)) : keccak256(abi.encodePacked(sibling, leaf));
        require(computed == root && !claimed[leaf], "invalid or already claimed");
        claimed[leaf] = true;
        require(token.transfer(recipient, amount));
    }
}
