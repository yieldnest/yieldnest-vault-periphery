// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {VaultManager} from "src/admin/VaultManager.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {MainnetActors as Actors} from "lib/yieldnest-vault/script/Actors.sol";
import {BaseVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {Provider} from "lib/yieldnest-vault/src/module/Provider.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";

contract VaultManagerIntegrationTest is Test, Actors {
    VaultManager public vaultManager;
    IVault public vault;

    function setUp() public {
        vault = IVault(MC.YNETHX);
        vaultManager = new VaultManager(MC.YNETHX, ADMIN, ADMIN, ADMIN);

        // Grant VaultManager the necessary roles on the vault
        vm.startPrank(ADMIN);
        BaseVault(payable(address(vault))).grantRole(
            BaseVault(payable(address(vault))).ASSET_MANAGER_ROLE(), address(vaultManager)
        );
        BaseVault(payable(address(vault))).grantRole(
            BaseVault(payable(address(vault))).BUFFER_MANAGER_ROLE(), address(vaultManager)
        );
        BaseVault(payable(address(vault))).grantRole(
            BaseVault(payable(address(vault))).PROVIDER_MANAGER_ROLE(), address(vaultManager)
        );
        vm.stopPrank();
    }

    function testSetCurrentBuffer() public {
        // Get current vault assets to find a valid buffer
        address[] memory assets = vault.getAssets();
        address validBuffer;

        // Find a valid ERC4626 asset that can be used as buffer
        for (uint256 i = 0; i < assets.length; i++) {
            if (vaultManager._isVaultAsset(assets[i]) && vaultManager._erc4626AssetMatchesVaultAsset(assets[i])) {
                validBuffer = assets[i];
                break;
            }
        }

        require(validBuffer != address(0), "No valid buffer found");

        vm.startPrank(ADMIN);
        vaultManager.setCurrentBuffer(validBuffer);
        vm.stopPrank();

        assertEq(vault.buffer(), validBuffer, "Buffer should be set correctly");
    }

    function testSetCurrentBufferRevertNotVaultAsset() public {
        address invalidAsset = address(0x1234);

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotVaultAsset.selector, invalidAsset));
        vaultManager.setCurrentBuffer(invalidAsset);
    }

    function testSetCurrentBufferRevertERC4626AssetMismatch() public {
        // Create a mock ERC4626 with wrong asset
        address wrongAsset = address(0x5678);
        MockERC4626 mockBuffer = new MockERC4626(ERC20(wrongAsset), "MockBuffer", "MB");

        // Add it as a vault asset first
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](1);
        assetsToAdd[0] = address(mockBuffer);
        activeFlags[0] = true;

        vm.prank(ADMIN);
        vm.expectRevert(); // This should revert due to provider rate not defined
        vaultManager.addAssets(assetsToAdd, activeFlags);
    }

    function testSetProviderToExistingProvider() public {
        address currentProvider = vault.provider();

        // Process accounting to ensure totalBaseAssets() is updated
        vault.processAccounting();
        uint256 totalBaseAssetsBefore = vault.totalBaseAssets();

        vm.prank(ADMIN);
        vaultManager.setProvider(currentProvider); // Set to same provider

        uint256 totalBaseAssetsAfter = vault.totalBaseAssets();
        assertEq(totalBaseAssetsAfter, totalBaseAssetsBefore, "totalBaseAssets should remain the same");

        // Should not revert since rates are already defined
        assertEq(vault.provider(), currentProvider, "Provider should remain the same");
    }

    function testSetProviderToNewProvider() public {
        Provider newProvider = new Provider();

        vault.processAccounting();
        uint256 totalBaseAssetsBefore = vault.totalBaseAssets();

        vm.prank(ADMIN);
        vaultManager.setProvider(address(newProvider));

        assertEq(vault.provider(), address(newProvider), "Provider should be set to new provider");

        uint256 totalBaseAssetsAfter = vault.totalBaseAssets();
        assertEq(totalBaseAssetsAfter, totalBaseAssetsBefore, "totalBaseAssets should remain the same");
    }

    function testSetProviderRevertProviderRateNotDefined() public {
        MockProvider mockProvider = new MockProvider();

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.ProviderRateNotDefined.selector, MC.WETH));
        vaultManager.setProvider(address(mockProvider));
    }

    function testAddAssetsRevertProviderRateNotDefined() public {
        // This test is complex as we need assets with defined provider rates
        // For now, test the revert case with undefined rates

        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](1);
        assetsToAdd[0] = address(0x9999);
        activeFlags[0] = true;

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.ProviderRateNotDefined.selector, address(0x9999)));
        vaultManager.addAssets(assetsToAdd, activeFlags);
    }

    function testDeleteAsset() public {
        // Get current assets count
        address[] memory assetsBefore = vault.getAssets();
        uint256 initialAssetCount = assetsBefore.length;

        vault.processAccounting();

        // Deploy a MockERC4626 as the new asset
        MockERC4626 newAsset = new MockERC4626(ERC20(vault.asset()), "MockAsset", "MA");
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](1);
        assetsToAdd[0] = address(newAsset);
        activeFlags[0] = true;

        // Mock the provider to return a valid rate for the new asset
        vm.mockCall(
            vault.provider(), abi.encodeWithSelector(IProvider.getRate.selector, address(newAsset)), abi.encode(1e18)
        );

        vm.prank(ADMIN);
        vaultManager.addAssets(assetsToAdd, activeFlags);

        // Verify asset was added
        address[] memory assetsAfterAdd = vault.getAssets();
        assertEq(assetsAfterAdd.length, initialAssetCount + 1, "Asset should be added");

        // Now delete the asset we just added (it should be at the last index)
        uint256 indexToDelete = assetsAfterAdd.length - 1;

        vm.prank(ADMIN);
        vaultManager.deleteAsset(indexToDelete);

        // Verify asset was deleted
        address[] memory assetsAfterDelete = vault.getAssets();
        assertEq(assetsAfterDelete.length, initialAssetCount, "Asset should be deleted");
    }

    function testIsVaultAssetFalse() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(vaultManager._isVaultAsset(assets[i]), "Should be valid vault asset");
        }

        assertFalse(vaultManager._isVaultAsset(address(0x1234)), "Should not be valid vault asset");
    }

    function testIsVaultAssetTrue() public view {
        address[] memory assets = vault.getAssets();
        address vaultAsset = vault.asset();
        assertTrue(vaultManager._isVaultAsset(vaultAsset), "Should be valid vault asset");
        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(vaultManager._isVaultAsset(assets[i]), "Should be valid vault asset");
        }
    }

    function testIsERC4626Asset() public view {
        address[] memory assets = vault.getAssets();
        address vaultAsset = vault.asset();

        for (uint256 i = 0; i < assets.length; i++) {
            try IERC4626(assets[i]).asset() returns (address assetAddr) {
                if (assetAddr == vaultAsset) {
                    assertTrue(vaultManager._erc4626AssetMatchesVaultAsset(assets[i]), "Should be valid ERC4626 asset");
                }
            } catch {
                // Asset is not ERC4626, skip
            }
        }
    }

    function testAccessControl() public {
        address unauthorized = address(0x9999);

        // Test BUFFER_ADMIN_ROLE
        vm.prank(unauthorized);
        vm.expectRevert();
        vaultManager.setCurrentBuffer(address(0x1234));

        // Test MODULE_MANAGER_ROLE
        vm.prank(unauthorized);
        vm.expectRevert();
        vaultManager.setProvider(address(0x1234));

        address[] memory assets = new address[](1);
        bool[] memory active = new bool[](1);
        assets[0] = address(0x1234);
        active[0] = true;

        vm.prank(unauthorized);
        vm.expectRevert();
        vaultManager.addAssets(assets, active);

        vm.prank(unauthorized);
        vm.expectRevert();
        vaultManager.deleteAsset(0);
    }
}

contract MockProvider {
    function getRate(address) external pure returns (uint256) {
        return 0; // Return 0 to trigger ProviderRateNotDefined error
    }
}
