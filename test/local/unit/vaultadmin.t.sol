// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {VaultManager} from "src/admin/VaultManager.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

// Use the AssetParams struct from IVault interface, as per file_context_1
struct AssetParams {
    uint256 index;
    bool active;
    uint8 decimals;
}

interface IVaultMock {
    function getAsset(address) external view returns (AssetParams memory);
    function asset() external view returns (address);
    function setBuffer(address) external;
}

contract VaultMock is IVaultMock {
    mapping(address => AssetParams) public assets;
    address public override asset;
    address public currentBuffer;
    address[] public allAssets;
    address public provider;
    address public lastProcessorTarget;
    uint256 public lastProcessorValue;
    bytes public lastProcessorCallData;

    function setAsset(address _addr, uint8 _decimals) external {
        assets[_addr] = AssetParams({index: allAssets.length, active: true, decimals: _decimals});
        allAssets.push(_addr);
    }

    function getAsset(address _addr) external view override returns (AssetParams memory) {
        return assets[_addr];
    }

    function setAssetAddress(address _asset) external {
        asset = _asset;
    }

    function setProvider(address _provider) external {
        provider = _provider;
    }

    function setBuffer(address _buffer) external override {
        currentBuffer = _buffer;
    }

    function getAssets() external view returns (address[] memory) {
        return allAssets;
    }

    function totalBaseAssets() external pure returns (uint256) {
        return 1e18;
    }

    function computeTotalAssets() external pure returns (uint256) {
        return 1e18;
    }

    function addAsset(address _addr, bool _active) external {
        assets[_addr] = AssetParams({index: allAssets.length, active: _active, decimals: 18});
        allAssets.push(_addr);
    }

    function deleteAsset(uint256 _index) external {
        uint256 lastIndex = allAssets.length - 1;
        address assetToDelete = allAssets[_index];
        address lastAsset = allAssets[lastIndex];

        if (_index != lastIndex) {
            allAssets[_index] = lastAsset;
            assets[lastAsset].index = _index;
        }

        allAssets.pop();
        delete assets[assetToDelete];
    }

    function processor(address[] memory _targets, uint256[] memory _values, bytes[] memory _data)
        external
        returns (bytes[] memory results)
    {
        lastProcessorTarget = _targets[0];
        lastProcessorValue = _values[0];
        lastProcessorCallData = _data[0];
        results = new bytes[](_targets.length);
    }
}

contract ERC4626Mock {
    address public asset_;

    constructor(address _asset) {
        asset_ = _asset;
    }

    function asset() external view returns (address) {
        return asset_;
    }
}

contract ProviderMock is IProvider {
    mapping(address => uint256) public rates;

    function setRate(address asset_, uint256 rate_) external {
        rates[asset_] = rate_;
    }

    function getRate(address asset_) external view returns (uint256) {
        return rates[asset_];
    }
}

contract VaultManagerUnitTest is Test {
    VaultManager vaultManager;
    VaultMock vault;
    address admin = address(0xA1);
    address bufferManagerRole = address(0xB1);
    address providerManagerRole = address(0xC1);
    address assetAdderRole = address(0xD1);
    address assetDeleterRole = address(0xE1);
    address processorRole = address(0xF1);

    address asset1 = address(0x1001);
    address asset2 = address(0x1002);

    ERC4626Mock erc4626_1;
    ERC4626Mock erc4626_2;
    ProviderMock provider;

    function setUp() public {
        vault = new VaultMock();
        vault.setAssetAddress(asset1);
        provider = new ProviderMock();

        // Set up ERC4626 mocks with correct asset
        erc4626_1 = new ERC4626Mock(asset1);
        erc4626_2 = new ERC4626Mock(asset1);

        // Set up vault assets
        vault.setAsset(address(erc4626_1), 18);
        vault.setAsset(address(erc4626_2), 18);
        provider.setRate(address(erc4626_1), 1e18);
        provider.setRate(address(erc4626_2), 1e18);
        vault.setProvider(address(provider));

        vaultManager = new VaultManager(
            address(vault),
            admin,
            bufferManagerRole,
            providerManagerRole,
            assetAdderRole,
            assetDeleterRole,
            processorRole
        );
    }

    function testSetCurrentBuffer() public {
        vm.startPrank(bufferManagerRole);

        // Valid buffer
        vaultManager.setCurrentBuffer(address(erc4626_1));
        assertEq(vault.currentBuffer(), address(erc4626_1), "currentBuffer should be set to erc4626_1");

        // Revert if not vault asset
        address nonAsset = address(0xbeef331);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotVaultAsset.selector, nonAsset));
        vaultManager.setCurrentBuffer(nonAsset);

        // Revert if ERC4626 asset mismatch
        ERC4626Mock wrongERC4626 = new ERC4626Mock(asset2);
        vault.setAsset(address(wrongERC4626), 18);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.ERC4626AssetMismatch.selector, address(wrongERC4626)));
        vaultManager.setCurrentBuffer(address(wrongERC4626));

        vm.stopPrank();
    }

    function testRolesAreDecoupledPerOperation() public {
        vm.prank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(erc4626_1));
        assertEq(vault.currentBuffer(), address(erc4626_1));

        vm.prank(providerManagerRole);
        vaultManager.setProvider(address(provider));
        assertEq(vault.provider(), address(provider));

        address newAsset = address(0x2001);
        provider.setRate(newAsset, 1e18);
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](1);
        assetsToAdd[0] = newAsset;
        activeFlags[0] = true;

        vm.prank(assetAdderRole);
        vaultManager.addAssets(assetsToAdd, activeFlags);
        assertEq(vault.getAssets().length, 3);

        vm.prank(assetDeleterRole);
        vaultManager.deleteAsset(2);
        assertEq(vault.getAssets().length, 2);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        values[0] = 1;
        data[0] = hex"1234";

        vm.prank(processorRole);
        vaultManager.processor(targets, values, data);
        assertEq(vault.lastProcessorTarget(), targets[0]);
        assertEq(vault.lastProcessorValue(), values[0]);
        assertEq(vault.lastProcessorCallData(), data[0]);

        vm.prank(bufferManagerRole);
        vm.expectRevert();
        vaultManager.setProvider(address(provider));

        vm.prank(providerManagerRole);
        vm.expectRevert();
        vaultManager.addAssets(assetsToAdd, activeFlags);

        vm.prank(assetAdderRole);
        vm.expectRevert();
        vaultManager.deleteAsset(0);

        vm.prank(assetDeleterRole);
        vm.expectRevert();
        vaultManager.processor(targets, values, data);
    }
}
