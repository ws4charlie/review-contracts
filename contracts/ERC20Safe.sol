// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title Manages ERC20 tokens.
contract ERC20Safe {
    using SafeMath for uint256;

    /// @notice Used to gain custody of tokens.
    /// @param tokenAddress Address of token.
    /// @param owner Address of current token owner.
    /// @param recipient Address to transfer tokens to.
    /// @param amount Amount of tokens to transfer.
    function lockERC20(address tokenAddress, address owner, address recipient, uint256 amount) internal {
        IERC20 erc20 = IERC20(tokenAddress);
        _safeTransferFrom(erc20, owner, recipient, amount);
    }

    /// @notice Transfers custody of token to recipient.
    /// @param tokenAddress Address of token.
    /// @param recipient Address to transfer tokens to.
    /// @param amount Amount of tokens to transfer.
    function releaseERC20(address tokenAddress, address recipient, uint256 amount) internal {
        IERC20 erc20 = IERC20(tokenAddress);
        _safeTransfer(erc20, recipient, amount);
    }

    /// @notice Used to transfer ERC20s safely.
    /// @param token Token contract.
    /// @param to Address to transfer token to.
    /// @param value Amount of token to transfer.
    function _safeTransfer(IERC20 token, address to, uint256 value) private {
        _safeCall(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /// @notice Used to transfer ERC20s safely
    /// @param token Token contract.
    /// @param from Address to transfer token from.
    /// @param to Address to transfer token to.
    /// @param value Amount of token to transfer.
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 value) private {
        _safeCall(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /// @notice Used to make calls to ERC20s safely
    /// @param token Token instance call targets
    /// @param data encoded call data
    function _safeCall(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, 'ERC20: call failed');

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), 'ERC20: operation failed');
        }
    }
}
