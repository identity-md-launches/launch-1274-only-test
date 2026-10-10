// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Only test (TEST)
/// @notice Fixed-supply, fee-free ERC-20. Launch distribution belongs to the external factory.
contract TESTToken {
    string public constant name = "Only test";
    string public constant symbol = "TEST";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address account => mapping(address spender => uint256 amount)) public allowance;

    /// @notice Gross successful outgoing transfers, in minor units, including self and zero transfers.
    /// @dev Minting is excluded. transferFrom attributes the amount to `from`, not the spender.
    mapping(address sender => uint256 amount) public cumulativeTransferred;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TransferRunningTotal(address indexed sender, uint256 cumulativeAmount);

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The deployer receives everything, including the factory's eventual swarm allocation.
    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (msg.sender == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < amount) revert ERC20InsufficientAllowance(msg.sender, approved, amount);
            unchecked {
                allowance[from][msg.sender] = approved - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 balance = balanceOf[from];
        if (balance < amount) revert ERC20InsufficientBalance(from, balance, amount);
        unchecked {
            balanceOf[from] = balance - amount;
            // Read after subtracting so self-transfers preserve the balance.
            balanceOf[to] += amount;
        }
        uint256 cumulative = cumulativeTransferred[from] + amount;
        cumulativeTransferred[from] = cumulative;
        emit Transfer(from, to, amount);
        emit TransferRunningTotal(from, cumulative);
    }
}

