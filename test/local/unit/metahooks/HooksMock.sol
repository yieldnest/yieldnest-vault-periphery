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

    function getConfig() external view override returns (Config memory) {
        return config;
    }

    function beforeDeposit(address, uint256, address, address, uint256, uint256) external override {
        beforeDepositCalled = true;
    }

    function afterDeposit(address, uint256, address, address, uint256, uint256) external override {
        afterDepositCalled = true;
    }

    function beforeMint(address, uint256, address, address, uint256, uint256) external override {
        beforeMintCalled = true;
    }

    function afterMint(address, uint256, address, address, uint256, uint256) external override {
        afterMintCalled = true;
    }

    function beforeRedeem(address, uint256, address, address, address, uint256) external override {
        beforeRedeemCalled = true;
    }

    function afterRedeem(address, uint256, address, address, address, uint256) external override {
        afterRedeemCalled = true;
    }

    function beforeWithdraw(address, uint256, address, address, address, uint256) external override {
        beforeWithdrawCalled = true;
    }

    function afterWithdraw(address, uint256, address, address, address, uint256) external override {
        afterWithdrawCalled = true;
    }

    function beforeProcessAccounting(uint256, uint256, uint256) external override {
        beforeProcessAccountingCalled = true;
    }

    function afterProcessAccounting(uint256, uint256, uint256, uint256, uint256, uint256) external override {
        afterProcessAccountingCalled = true;
    }

    function VAULT() external pure returns (IVault) {
        return IVault(address(0));
    }

    function setConfig(Config memory) external pure {}
}
