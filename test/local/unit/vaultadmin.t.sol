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
    function hasAsset(address) external view returns (bool);
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
    uint256 public processAccountingCalls;
    uint256 public totalAssetsValue = 1e18;
    uint256 public totalSupplyValue = 1e18;
    uint256 public nextTotalAssetsValue = 1e18;
    uint256 public nextTotalSupplyValue = 1e18;

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

    function buffer() external view returns (address) {
        return currentBuffer;
    }

    function getAssets() external view returns (address[] memory) {
        return allAssets;
    }

    function hasAsset(address _asset) external view returns (bool) {
        if (allAssets.length == 0) return false;
        uint256 index = assets[_asset].index;
        return index < allAssets.length && allAssets[index] == _asset;
    }

    function totalBaseAssets() external pure returns (uint256) {
        return 1e18;
    }

    function computeTotalAssets() external pure returns (uint256) {
        return 1e18;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function totalSupply() external view returns (uint256) {
        return totalSupplyValue;
    }

    function setAccountingSnapshot(uint256 _totalAssets, uint256 _totalSupply) external {
        totalAssetsValue = _totalAssets;
        totalSupplyValue = _totalSupply;
        nextTotalAssetsValue = _totalAssets;
        nextTotalSupplyValue = _totalSupply;
    }

    function setNextAccountingSnapshot(uint256 _totalAssets, uint256 _totalSupply) external {
        nextTotalAssetsValue = _totalAssets;
        nextTotalSupplyValue = _totalSupply;
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
        totalAssetsValue = nextTotalAssetsValue;
        totalSupplyValue = nextTotalSupplyValue;
        results = new bytes[](_targets.length);
        for (uint256 i = 0; i < _targets.length; ++i) {
            results[i] = abi.encode(_targets[i], _values[i], _data[i]);
        }
    }

    function processAccounting() external {
        processAccountingCalls += 1;
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
        vault.setAccountingSnapshot(1e18, 1e18);
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
        vaultManager.deleteAsset(newAsset);
        assertEq(vault.getAssets().length, 2);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        values[0] = 1;
        data[0] = hex"1234";

        vm.prank(processorRole);
        bytes[] memory results = vaultManager.processor(targets, values, data);
        assertEq(vault.lastProcessorTarget(), targets[0]);
        assertEq(vault.lastProcessorValue(), values[0]);
        assertEq(vault.lastProcessorCallData(), data[0]);
        assertEq(vault.processAccountingCalls(), 1);
        assertEq(results.length, 1);
        assertEq(results[0], abi.encode(targets[0], values[0], data[0]));

        vm.prank(bufferManagerRole);
        vm.expectRevert();
        vaultManager.setProvider(address(provider));

        vm.prank(providerManagerRole);
        vm.expectRevert();
        vaultManager.addAssets(assetsToAdd, activeFlags);

        vm.prank(assetAdderRole);
        vm.expectRevert();
        vaultManager.deleteAsset(address(erc4626_1));

        vm.prank(assetDeleterRole);
        vm.expectRevert();
        vaultManager.processor(targets, values, data);
    }

    function testDeleteAssetRevertsForBuffer() public {
        vm.prank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(erc4626_1));

        vm.prank(assetDeleterRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.CannotDeleteBufferAsset.selector, address(erc4626_1)));
        vaultManager.deleteAsset(address(erc4626_1));
    }

    function testDeleteAssetsRevertsForDuplicates() public {
        address[] memory assetsToDelete = new address[](2);
        assetsToDelete[0] = address(erc4626_1);
        assetsToDelete[1] = address(erc4626_1);

        vm.prank(assetDeleterRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.DuplicateAsset.selector, address(erc4626_1)));
        vaultManager.deleteAssets(assetsToDelete);
    }

    function testAddAssetsRevertsOnLengthMismatch() public {
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](0);
        assetsToAdd[0] = address(0x2001);

        vm.prank(assetAdderRole);
        vm.expectRevert(VaultManager.LengthMismatch.selector);
        vaultManager.addAssets(assetsToAdd, activeFlags);
    }

    function testProcessorRevertsOnLengthMismatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](0);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        data[0] = hex"1234";

        vm.prank(processorRole);
        vm.expectRevert(VaultManager.LengthMismatch.selector);
        vaultManager.processor(targets, values, data);
    }

    function testSetMaxProcessorDeltaRatio() public {
        vm.prank(admin);
        vaultManager.setMaxProcessorDeltaRatio(0.05e18);

        assertEq(vaultManager.maxProcessorDeltaRatio(), 0.05e18);
    }

    function testSetMaxProcessorDeltaRatioRevertsAboveDenominator() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.RatioTooHigh.selector, 1e18 + 1));
        vaultManager.setMaxProcessorDeltaRatio(1e18 + 1);
    }

    function testProcessorRevertsWhenTotalAssetsDeltaExceeded() public {
        vm.prank(admin);
        vaultManager.setMaxProcessorDeltaRatio(0.05e18);

        vault.setAccountingSnapshot(100e18, 100e18);
        vault.setNextAccountingSnapshot(107e18, 100e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        data[0] = hex"1234";

        vm.prank(processorRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.TotalAssetsDeltaExceeded.selector, 100e18, 107e18));
        vaultManager.processor(targets, values, data);
    }

    function testProcessorRevertsWhenTotalSupplyDeltaExceeded() public {
        vm.prank(admin);
        vaultManager.setMaxProcessorDeltaRatio(0.05e18);

        vault.setAccountingSnapshot(100e18, 100e18);
        vault.setNextAccountingSnapshot(100e18, 107e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        data[0] = hex"1234";

        vm.prank(processorRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.TotalSupplyDeltaExceeded.selector, 100e18, 107e18));
        vaultManager.processor(targets, values, data);
    }

    function testProcessorAllowsConfiguredDeltaForAssetsAndSupply() public {
        vm.prank(admin);
        vaultManager.setMaxProcessorDeltaRatio(0.05e18);

        vault.setAccountingSnapshot(100e18, 100e18);
        vault.setNextAccountingSnapshot(105e18, 95e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x3001);
        data[0] = hex"1234";

        vm.prank(processorRole);
        bytes[] memory results = vaultManager.processor(targets, values, data);

        assertEq(vault.processAccountingCalls(), 1);
        assertEq(vault.totalAssets(), 105e18);
        assertEq(vault.totalSupply(), 95e18);
        assertEq(results.length, 1);
        assertEq(results[0], abi.encode(targets[0], values[0], data[0]));
    }
}
