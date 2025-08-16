// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract MetaHooks is IHooks {
    IVault public immutable override VAULT;

    Config private _config;

    constructor(address vault_) {
        require(vault_ != address(0), "MetaHooks: vault is zero address");
        VAULT = IVault(vault_);
    }


    function addHooks(address[] memory hooks_) external {

    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }



    function setConfig(Config memory config_) external override {
        _config = config_;
    }

    function getConfig() external view override returns (Config memory) {
        return _config;
    }

    function beforeDeposit(
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyVault {
        if (!_config.beforeDeposit) return;
        // Custom logic can be implemented here
    }

    function afterDeposit(
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyVault {
        if (!_config.afterDeposit) return;
        // Custom logic can be implemented here
    }

    function beforeMint(
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override onlyVault {
        if (!_config.beforeMint) return;
        // Custom logic can be implemented here
    }

    function afterMint(
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override onlyVault {
        if (!_config.afterMint) return;
        // Custom logic can be implemented here
    }

    function beforeRedeem(
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external override onlyVault {
        if (!_config.beforeRedeem) return;
        // Custom logic can be implemented here
    }

    function afterRedeem(
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external override onlyVault {
        if (!_config.afterRedeem) return;
        // Custom logic can be implemented here
    }

    function beforeWithdraw(
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external override onlyVault {
        if (!_config.beforeWithdraw) return;
        // Custom logic can be implemented here
    }

    function afterWithdraw(
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external override onlyVault {
        if (!_config.afterWithdraw) return;
        // Custom logic can be implemented here
    }

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        if (!_config.beforeProcessAccounting) return;
        // Custom logic can be implemented here
    }

    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseBalanceAfterAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        if (!_config.afterProcessAccounting) return;
        // Custom logic can be implemented here
    }

}
