// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWithdrawAssetVault is IERC20 {
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);
}

/// @title WithdrawalRequestManager
/// @notice Custodies one yn-token type and tracks permissioned fulfilment of withdrawal requests.
contract WithdrawalRequestManager is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.1.0";

    struct WithdrawalRequest {
        address owner;
        uint256 amountLocked;
    }

    /// @custom:storage-location erc7201:yieldnest.storage.withdrawal_request_manager
    struct WithdrawalRequestManagerStorage {
        IWithdrawAssetVault token;
        uint256 minimumAmountToLock;
        uint256 nextRequestId;
        mapping(uint256 id => WithdrawalRequest request) requests;
    }

    error ZeroAddress();
    error ZeroAmount();
    error AmountBelowMinimum(uint256 amount, uint256 minimumAmountToLock);
    error RequestNotFound(uint256 id);
    error InsufficientLockedAmount(uint256 id, uint256 amountLocked, uint256 amountBurned);
    error InvalidTokenBalanceChange(uint256 balanceBefore, uint256 balanceAfter);
    error InvalidAssetBalanceChange(uint256 balanceBefore, uint256 balanceAfter);
    error UnexpectedAssetsWithdrawn(uint256 expectedAssets, uint256 actualAssets);

    event WithdrawalRequested(uint256 indexed id, address indexed owner, address indexed token, uint256 amountLocked);
    event WithdrawalRequestFulfilled(
        uint256 indexed id,
        address indexed owner,
        address indexed token,
        address asset,
        uint256 assetsWithdrawn,
        uint256 amountBurned,
        uint256 amountLocked
    );
    event MinimumAmountToLockUpdated(uint256 oldMinimumAmountToLock, uint256 newMinimumAmountToLock);

    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant CONFIGURATION_MANAGER_ROLE = keccak256("CONFIGURATION_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // keccak256(abi.encode(uint256(keccak256("yieldnest.storage.withdrawal_request_manager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WithdrawalRequestManagerStorageLocation =
        0x15a0bae20a3f0267f2acf0f91b407bda6fc5d0eeb31acffcadb37a1c9e929100;

    function _getWithdrawalRequestManagerStorage() private pure returns (WithdrawalRequestManagerStorage storage $) {
        assembly {
            $.slot := WithdrawalRequestManagerStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address token_,
        address defaultAdmin,
        address fulfiller,
        address configurationManager,
        address pauser,
        uint256 minimumAmountToLock_
    ) external initializer {
        if (
            token_ == address(0) || defaultAdmin == address(0) || fulfiller == address(0)
                || configurationManager == address(0) || pauser == address(0)
        ) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __Pausable_init();

        WithdrawalRequestManagerStorage storage $ = _getWithdrawalRequestManagerStorage();
        $.token = IWithdrawAssetVault(token_);
        $.minimumAmountToLock = minimumAmountToLock_;
        $.nextRequestId = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(FULFILLER_ROLE, fulfiller);
        _grantRole(CONFIGURATION_MANAGER_ROLE, configurationManager);
        _grantRole(PAUSER_ROLE, pauser);
    }

    // --- Configuration ---

    function setMinimumAmountToLock(uint256 minimumAmountToLock_) external onlyRole(CONFIGURATION_MANAGER_ROLE) {
        WithdrawalRequestManagerStorage storage $ = _getWithdrawalRequestManagerStorage();
        uint256 oldMinimumAmountToLock = $.minimumAmountToLock;
        $.minimumAmountToLock = minimumAmountToLock_;

        emit MinimumAmountToLockUpdated(oldMinimumAmountToLock, minimumAmountToLock_);
    }

    // --- Requests ---

    /// @notice Locks yn-tokens in this contract and creates a withdrawal request.
    /// @param amount Amount of configured yn-token shares to lock.
    /// @return id Generated request id.
    function requestWithdrawal(uint256 amount) external whenNotPaused returns (uint256 id) {
        if (amount == 0) revert ZeroAmount();

        WithdrawalRequestManagerStorage storage $ = _getWithdrawalRequestManagerStorage();
        if (amount < $.minimumAmountToLock) revert AmountBelowMinimum(amount, $.minimumAmountToLock);

        id = $.nextRequestId++;
        $.requests[id] = WithdrawalRequest({owner: msg.sender, amountLocked: amount});

        IERC20(address($.token)).safeTransferFrom(msg.sender, address(this), amount);

        emit WithdrawalRequested(id, msg.sender, address($.token), amount);
    }

    // --- Fulfillment ---

    /// @notice Fulfils part or all of a request by withdrawing an asset from the configured yn-token.
    /// @param id Request id to fulfil.
    /// @param asset Asset to withdraw from the yn-token.
    /// @param assets Amount of `asset` to withdraw to this contract.
    /// @return amountBurned Amount of locked yn-token shares burned by the withdrawal.
    function fulfillWithdrawalRequest(uint256 id, address asset, uint256 assets)
        external
        onlyRole(FULFILLER_ROLE)
        returns (uint256 amountBurned)
    {
        if (asset == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroAmount();

        WithdrawalRequestManagerStorage storage $ = _getWithdrawalRequestManagerStorage();
        WithdrawalRequest storage request = $.requests[id];
        if (request.owner == address(0)) revert RequestNotFound(id);

        uint256 tokenBalanceBefore = $.token.balanceOf(address(this));
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));

        $.token.withdrawAsset(asset, assets, address(this), address(this));

        uint256 tokenBalanceAfter = $.token.balanceOf(address(this));
        if (tokenBalanceAfter > tokenBalanceBefore) {
            revert InvalidTokenBalanceChange(tokenBalanceBefore, tokenBalanceAfter);
        }

        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        if (assetBalanceAfter < assetBalanceBefore) {
            revert InvalidAssetBalanceChange(assetBalanceBefore, assetBalanceAfter);
        }

        amountBurned = tokenBalanceBefore - tokenBalanceAfter;
        if (amountBurned > request.amountLocked) {
            revert InsufficientLockedAmount(id, request.amountLocked, amountBurned);
        }

        uint256 assetsWithdrawn = assetBalanceAfter - assetBalanceBefore;
        if (assetsWithdrawn != assets) revert UnexpectedAssetsWithdrawn(assets, assetsWithdrawn);

        request.amountLocked -= amountBurned;
        IERC20(asset).safeTransfer(request.owner, assetsWithdrawn);

        emit WithdrawalRequestFulfilled(
            id, request.owner, address($.token), asset, assetsWithdrawn, amountBurned, request.amountLocked
        );
    }

    // --- Getters ---

    function token() public view returns (IWithdrawAssetVault) {
        return _getWithdrawalRequestManagerStorage().token;
    }

    function minimumAmountToLock() public view returns (uint256) {
        return _getWithdrawalRequestManagerStorage().minimumAmountToLock;
    }

    function nextRequestId() public view returns (uint256) {
        return _getWithdrawalRequestManagerStorage().nextRequestId;
    }

    function requests(uint256 id) public view returns (WithdrawalRequest memory) {
        return _getWithdrawalRequestManagerStorage().requests[id];
    }

    // --- Pause ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
