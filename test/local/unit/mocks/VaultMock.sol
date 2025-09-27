// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";

// Minimal mock for IVault
contract VaultMock is IVaultForHooks {
    address public asset_;
    mapping(address => uint256) public mintedShares;
    uint256 public assetsToShares;
    uint256 public feeOnRaw;
    uint256 public feeOnTotal;
    uint256 public totalSupply_;
    uint256 public totalAssets_;
    bool public alwaysComputeTotalAssets_;

    constructor(address _asset) {
        asset_ = _asset;
    }

    function setTotalSupply(uint256 _totalSupply) external {
        totalSupply_ = _totalSupply;
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssets_ = _totalAssets;
    }

    function asset() external view override returns (address) {
        return asset_;
    }

    function mintShares(address to, uint256 shares) external override {
        mintedShares[to] += shares;
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return assetsToShares + assets;
    }

    function _feeOnRaw(uint256 assets, address) external view override returns (uint256) {
        return feeOnRaw + assets;
    }

    function _feeOnTotal(uint256 shares, address) external view override returns (uint256) {
        return feeOnTotal + shares;
    }

    function previewDepositAsset(address, /* assetAddress */ uint256 assets) external view override returns (uint256) {
        return assetsToShares + assets;
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return assetsToShares + shares;
    }

    function totalSupply() external view override returns (uint256) {
        return totalSupply_;
    }

    function totalAssets() external view override returns (uint256) {
        return totalAssets_;
    }

    function setAlwaysComputeTotalAssets(bool _alwaysComputeTotalAssets) external {
        alwaysComputeTotalAssets_ = _alwaysComputeTotalAssets;
    }

    function alwaysComputeTotalAssets() external view override returns (bool) {
        return alwaysComputeTotalAssets_;
    }
}
