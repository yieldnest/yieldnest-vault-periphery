// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BufferAdmin} from "../../src/admin/BufferAdmin.sol";

interface IVaultMock {
    function getAsset(address) external view returns (Asset memory);
    function asset() external view returns (address);
    function setBuffer(address) external;
}

struct Asset {
    uint8 decimals;
}

contract VaultMock is IVaultMock {
    mapping(address => Asset) public assets;
    address public override asset;
    address public currentBuffer;

    function setAsset(address _addr, uint8 _decimals) external {
        assets[_addr] = Asset(_decimals);
    }

    function getAsset(address _addr) external view override returns (Asset memory) {
        return assets[_addr];
    }

    function setAssetAddress(address _asset) external {
        asset = _asset;
    }

    function setBuffer(address _buffer) external override {
        currentBuffer = _buffer;
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

contract BufferAdminUnitTest is Test {
    BufferAdmin bufferAdmin;
    VaultMock vault;
    address admin = address(0xA1);
    address bufferAdminRole = address(0xB1);

    address asset1 = address(0x1001);
    address asset2 = address(0x1002);

    ERC4626Mock erc4626_1;
    ERC4626Mock erc4626_2;

    function setUp() public {
        vault = new VaultMock();
        vault.setAssetAddress(asset1);

        // Set up ERC4626 mocks with correct asset
        erc4626_1 = new ERC4626Mock(asset1);
        erc4626_2 = new ERC4626Mock(asset1);

        // Set up vault assets
        vault.setAsset(address(erc4626_1), 18);
        vault.setAsset(address(erc4626_2), 18);

        bufferAdmin = new BufferAdmin(address(vault), admin, bufferAdminRole);
    }

    function testSetCurrentBuffer() public {
        vm.startPrank(bufferAdminRole);

        // Valid buffer
        bufferAdmin.setCurrentBuffer(address(erc4626_1));
        assertEq(vault.currentBuffer(), address(erc4626_1));

        // Revert if not vault asset
        vault.setAsset(address(erc4626_1), 0);
        vm.expectRevert(BufferAdmin.NotVaultAsset.selector);
        bufferAdmin.setCurrentBuffer(address(erc4626_1));

        // Revert if ERC4626 asset mismatch
        ERC4626Mock wrongERC4626 = new ERC4626Mock(asset2);
        vault.setAsset(address(wrongERC4626), 18);
        vm.expectRevert(BufferAdmin.ERC4626AssetMismatch.selector);
        bufferAdmin.setCurrentBuffer(address(wrongERC4626));

        vm.stopPrank();
    }
}
