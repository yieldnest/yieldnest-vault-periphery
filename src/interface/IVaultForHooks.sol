// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVaultForHooks {
    function mintShares(address to, uint256 shares) external;
    function convertToShares(uint256 assets) external view returns (uint256);
    function asset() external view returns (address);
    function _feeOnRaw(uint256 assets, address caller) external view returns (uint256);
    function _feeOnTotal(uint256 shares, address caller) external view returns (uint256);
    function previewDepositAsset(address assetAddress, uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function alwaysComputeTotalAssets() external view returns (bool);
}
