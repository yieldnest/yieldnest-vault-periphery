// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

// Minimal mock for IHooks
contract HooksMock is IHooks {
    Config public config;
    bool public beforeDepositCalled;
    bool public afterDepositCalled;
    bool public beforeMintCalled;
    bool public afterMintCalled;
    bool public beforeRedeemCalled;
    bool public afterRedeemCalled;
    bool public beforeWithdrawCalled;
    bool public afterWithdrawCalled;
    bool public beforeProcessAccountingCalled;
    bool public afterProcessAccountingCalled;

    constructor(Config memory _config) {
        config = _config;
    }

    function name() external pure override returns (string memory) {
        return "HooksMock";
    }

    function getConfig() external view override returns (Config memory) {
        return config;
    }

    function beforeDeposit(DepositParams memory) external override {
        beforeDepositCalled = true;
    }

    function afterDeposit(DepositParams memory) external override {
        afterDepositCalled = true;
    }

    function beforeMint(MintParams memory) external override {
        beforeMintCalled = true;
    }

    function afterMint(MintParams memory) external override {
        afterMintCalled = true;
    }

    function beforeRedeem(RedeemParams memory) external override {
        beforeRedeemCalled = true;
    }

    function afterRedeem(RedeemParams memory) external override {
        afterRedeemCalled = true;
    }

    function beforeWithdraw(WithdrawParams memory) external override {
        beforeWithdrawCalled = true;
    }

    function afterWithdraw(WithdrawParams memory) external override {
        afterWithdrawCalled = true;
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external override {
        beforeProcessAccountingCalled = true;
    }

    function afterProcessAccounting(AfterProcessAccountingParams memory) external override {
        afterProcessAccountingCalled = true;
    }

    function VAULT() external pure returns (IVault) {
        return IVault(address(0));
    }

    function setConfig(Config memory _config) external {
        config = _config;
    }
}
