// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title PauserHook
/// @notice Hook-level circuit breaker for vault operations.
contract PauserHook is IHooks, AccessControl {
    string public constant VERSION = "0.1.0";

    enum HookCall {
        Deposit,
        Mint,
        Redeem,
        Withdraw,
        ProcessAccounting
    }

    error OnlyVault();
    error Paused(HookCall hookCall);
    error NotSupported();

    event HookCallPaused(HookCall indexed hookCall);
    event HookCallUnpaused(HookCall indexed hookCall);
    event AlreadyPaused(HookCall indexed hookCall);
    event AlreadyUnpaused(HookCall indexed hookCall);

    IVault public immutable override VAULT;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    mapping(HookCall hookCall => bool paused) public paused;

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    constructor(address vault_, address defaultAdmin, address pauser, address unpauser) {
        VAULT = IVault(vault_);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UNPAUSER_ROLE, unpauser);
    }

    /// @inheritdoc IHooks
    function name() external pure override returns (string memory) {
        return "PauserHook";
    }

    function pause(HookCall hookCall) external onlyRole(PAUSER_ROLE) {
        if (paused[hookCall]) {
            emit AlreadyPaused(hookCall);
            return;
        }

        paused[hookCall] = true;
        emit HookCallPaused(hookCall);
    }

    function unpause(HookCall hookCall) external onlyRole(UNPAUSER_ROLE) {
        if (!paused[hookCall]) {
            emit AlreadyUnpaused(hookCall);
            return;
        }

        paused[hookCall] = false;
        emit HookCallUnpaused(hookCall);
    }

    function getConfig() external pure override returns (Config memory) {
        return Config({
            beforeDeposit: true,
            afterDeposit: true,
            beforeMint: true,
            afterMint: true,
            beforeRedeem: true,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: true,
            beforeProcessAccounting: true,
            afterProcessAccounting: true
        });
    }

    /// @inheritdoc IHooks
    function setConfig(Config memory) external pure override {
        revert NotSupported();
    }

    function beforeDeposit(DepositParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Deposit);
    }

    function afterDeposit(DepositParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Deposit);
    }

    function beforeMint(MintParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Mint);
    }

    function afterMint(MintParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Mint);
    }

    function beforeRedeem(RedeemParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Redeem);
    }

    function afterRedeem(RedeemParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Redeem);
    }

    function beforeWithdraw(WithdrawParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Withdraw);
    }

    function afterWithdraw(WithdrawParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.Withdraw);
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.ProcessAccounting);
    }

    function afterProcessAccounting(AfterProcessAccountingParams memory) external view override onlyVault {
        _requireNotPaused(HookCall.ProcessAccounting);
    }

    function _requireNotPaused(HookCall hookCall) internal view {
        if (paused[hookCall]) revert Paused(hookCall);
    }
}
