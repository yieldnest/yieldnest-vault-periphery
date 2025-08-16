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
    address asset3 = address(0x1003);

    ERC4626Mock erc4626_1;
    ERC4626Mock erc4626_2;
    ERC4626Mock erc4626_3;

    function setUp() public {
        vault = new VaultMock();
        vault.setAssetAddress(asset1);

        // Set up ERC4626 mocks with correct asset
        erc4626_1 = new ERC4626Mock(asset1);
        erc4626_2 = new ERC4626Mock(asset1);
        erc4626_3 = new ERC4626Mock(asset1);

        // Set up vault assets
        vault.setAsset(address(erc4626_1), 18);
        vault.setAsset(address(erc4626_2), 18);
        vault.setAsset(address(erc4626_3), 18);

        bufferAdmin = new BufferAdmin(address(vault), admin, bufferAdminRole);
    }

    function testAddBuffers() public {
        vm.prank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufferAdmin.addBuffers(bufs);

        assertTrue(bufferAdmin.isBuffer(address(erc4626_1)));
        assertTrue(bufferAdmin.isBuffer(address(erc4626_2)));
        assertEq(bufferAdmin.buffers(0), address(erc4626_1));
        assertEq(bufferAdmin.buffers(1), address(erc4626_2));
    }

    function testAddBufferRevertsIfDuplicateInInput() public {
        vm.prank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_1);
        vm.expectRevert(BufferAdmin.DuplicateBuffer.selector);
        bufferAdmin.addBuffers(bufs);
    }

    function testAddBufferRevertsIfAlreadyAdded() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](1);
        bufs[0] = address(erc4626_1);
        bufferAdmin.addBuffers(bufs);

        address[] memory bufs2 = new address[](1);
        bufs2[0] = address(erc4626_1);
        vm.expectRevert(BufferAdmin.BufferAlreadyAdded.selector);
        bufferAdmin.addBuffers(bufs2);
        vm.stopPrank();
    }

    function testAddBufferRevertsIfNotVaultAsset() public {
        vm.prank(bufferAdminRole);
        address fake = address(0xdeadbeef);
        address[] memory bufs = new address[](1);
        bufs[0] = fake;
        vm.expectRevert(BufferAdmin.NotVaultAsset.selector);
        bufferAdmin.addBuffers(bufs);
    }

    function testAddBufferRevertsIfERC4626AssetMismatch() public {
        // ERC4626Mock with wrong asset
        ERC4626Mock wrongERC4626 = new ERC4626Mock(asset2);
        vault.setAsset(address(wrongERC4626), 18);

        vm.prank(bufferAdminRole);
        address[] memory bufs = new address[](1);
        bufs[0] = address(wrongERC4626);
        vm.expectRevert(BufferAdmin.ERC4626AssetMismatch.selector);
        bufferAdmin.addBuffers(bufs);
    }

    function testRemoveBuffers() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufferAdmin.addBuffers(bufs);

        address[] memory removeBufs = new address[](1);
        removeBufs[0] = address(erc4626_1);
        bufferAdmin.removeBuffers(removeBufs);

        assertFalse(bufferAdmin.isBuffer(address(erc4626_1)));
        assertTrue(bufferAdmin.isBuffer(address(erc4626_2)));
        vm.stopPrank();
    }

    function testRemoveBufferRevertsIfNotFound() public {
        vm.prank(bufferAdminRole);
        address[] memory bufs = new address[](1);
        bufs[0] = address(erc4626_1);
        vm.expectRevert(BufferAdmin.BufferNotFound.selector);
        bufferAdmin.removeBuffers(bufs);
    }

    function testUpdateBufferOrder() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](3);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufs[2] = address(erc4626_3);
        bufferAdmin.addBuffers(bufs);

        address[] memory newOrder = new address[](3);
        newOrder[0] = address(erc4626_3);
        newOrder[1] = address(erc4626_2);
        newOrder[2] = address(erc4626_1);
        bufferAdmin.updateBufferOrder(newOrder);

        assertEq(bufferAdmin.buffers(0), address(erc4626_3));
        assertEq(bufferAdmin.buffers(1), address(erc4626_2));
        assertEq(bufferAdmin.buffers(2), address(erc4626_1));
        vm.stopPrank();
    }

    function testUpdateBufferOrderRevertsIfLengthMismatch() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufferAdmin.addBuffers(bufs);

        address[] memory newOrder = new address[](1);
        newOrder[0] = address(erc4626_1);
        vm.expectRevert(BufferAdmin.LengthMismatch.selector);
        bufferAdmin.updateBufferOrder(newOrder);
        vm.stopPrank();
    }

    function testUpdateBufferOrderRevertsIfNotInSet() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufferAdmin.addBuffers(bufs);

        address[] memory newOrder = new address[](2);
        newOrder[0] = address(erc4626_1);
        newOrder[1] = address(erc4626_3); // not in set
        vm.expectRevert(BufferAdmin.BufferNotFound.selector);
        bufferAdmin.updateBufferOrder(newOrder);
        vm.stopPrank();
    }

    function testUpdateBufferOrderRevertsIfDuplicate() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](2);
        bufs[0] = address(erc4626_1);
        bufs[1] = address(erc4626_2);
        bufferAdmin.addBuffers(bufs);

        address[] memory newOrder = new address[](2);
        newOrder[0] = address(erc4626_1);
        newOrder[1] = address(erc4626_1);
        vm.expectRevert(BufferAdmin.DuplicateBuffer.selector);
        bufferAdmin.updateBufferOrder(newOrder);
        vm.stopPrank();
    }

    function testSetCurrentBuffer() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](1);
        bufs[0] = address(erc4626_1);
        bufferAdmin.addBuffers(bufs);

        bufferAdmin.setCurrentBuffer(address(erc4626_1));
        assertEq(vault.currentBuffer(), address(erc4626_1));
        vm.stopPrank();
    }

    function testSetCurrentBufferRevertsIfNotInList() public {
        vm.prank(bufferAdminRole);
        vm.expectRevert(BufferAdmin.BufferNotInList.selector);
        bufferAdmin.setCurrentBuffer(address(erc4626_1));
    }

    function testSetCurrentBufferRevertsIfNotVaultAsset() public {
        vm.startPrank(bufferAdminRole);
        address[] memory bufs = new address[](1);
        bufs[0] = address(erc4626_1);
        bufferAdmin.addBuffers(bufs);

        // Remove asset from vault
        vault.setAsset(address(erc4626_1), 0);

        vm.expectRevert(BufferAdmin.NotVaultAsset.selector);
        bufferAdmin.setCurrentBuffer(address(erc4626_1));
        vm.stopPrank();
    }
}
