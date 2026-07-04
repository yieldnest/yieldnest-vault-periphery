// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @title Bag
/// @notice Per-request NFT container whose token owner can claim received assets.
contract Bag is Initializable, ERC721Upgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant TOKEN_ID = 1;

    error ZeroAddress();
    error NotBagOwner(address caller);

    event Claimed(address indexed owner, address indexed recipient, address indexed asset, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the bag NFT and mints it to the owner.
    /// @param owner_ Initial owner of the bag NFT.
    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();

        __ERC721_init("YieldNest Withdrawal Bag", "ynBAG");
        _mint(owner_, TOKEN_ID);
    }

    /// @notice Claims this bag's full balance of an asset.
    /// @param asset Asset to claim.
    /// @param recipient Receiver of the claimed asset.
    /// @return amount Amount claimed.
    function claim(address asset, address recipient) external returns (uint256 amount) {
        if (msg.sender != ownerOf(TOKEN_ID)) revert NotBagOwner(msg.sender);
        if (asset == address(0) || recipient == address(0)) revert ZeroAddress();

        amount = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(recipient, amount);

        emit Claimed(msg.sender, recipient, asset, amount);
    }
}
