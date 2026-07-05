// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBag} from "src/interface/IBag.sol";

/// @title Bag
/// @notice Per-request NFT container whose token owner can claim received assets.
contract Bag is Initializable, ERC721Upgradeable, IBag {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.1.0";
    uint256 public constant TOKEN_ID = 1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyNFTOwner() {
        if (msg.sender != ownerOf(TOKEN_ID)) revert NotBagOwner(msg.sender);
        _;
    }

    receive() external payable {}

    /// @notice Initializes the bag NFT and mints it to the owner.
    /// @param owner_ Initial owner of the bag NFT.
    /// @param requestId Withdrawal request id represented by this bag.
    function initialize(address owner_, uint256 requestId) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();

        string memory requestIdString = Strings.toString(requestId);
        __ERC721_init(
            string.concat("YieldNest Withdrawal Bag #", requestIdString), string.concat("ynBAG-", requestIdString)
        );
        _mint(owner_, TOKEN_ID);
    }

    /// @notice Claims this bag's full balance of an ERC20 asset.
    /// @param asset Asset to claim.
    /// @param recipient Receiver of the claimed asset.
    /// @return amount Amount claimed.
    function claimERC20(address asset, address recipient) external onlyNFTOwner returns (uint256 amount) {
        if (asset == address(0) || recipient == address(0)) revert ZeroAddress();

        amount = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(recipient, amount);

        emit ERC20Claimed(msg.sender, recipient, asset, amount);
    }

    /// @notice Claims an ERC721 token held by this bag.
    /// @param asset ERC721 asset to claim.
    /// @param recipient Receiver of the claimed token.
    /// @param tokenId Token id to claim.
    function claimERC721(address asset, address recipient, uint256 tokenId) external onlyNFTOwner {
        if (asset == address(0) || recipient == address(0)) revert ZeroAddress();

        IERC721(asset).safeTransferFrom(address(this), recipient, tokenId);

        emit ERC721Claimed(msg.sender, recipient, asset, tokenId);
    }

    /// @notice Claims this bag's full native ETH balance.
    /// @param recipient Receiver of the claimed native ETH.
    /// @return amount Amount claimed.
    function claimNative(address payable recipient) external onlyNFTOwner returns (uint256 amount) {
        if (recipient == address(0)) revert ZeroAddress();

        amount = address(this).balance;
        recipient.transfer(amount);

        emit NativeClaimed(msg.sender, recipient, amount);
    }
}
