// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {Bag} from "src/withdrawal/Bag.sol";
import {BaseBeaconMaker} from "src/withdrawal/BaseBeaconMaker.sol";
import {WithdrawalRequestManager} from "src/withdrawal/WithdrawalRequestManager.sol";

contract MockWithdrawAssetVault is ERC20 {
    uint256 public burnMultiplier = 1;
    uint256 public returnAmountOffset;
    uint256 public transferShortfall;
    uint256 public processAccountingCalls;

    constructor() ERC20("ynToken", "ynT") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setBurnMultiplier(uint256 burnMultiplier_) external {
        burnMultiplier = burnMultiplier_;
    }

    function setReturnAmountOffset(uint256 returnAmountOffset_) external {
        returnAmountOffset = returnAmountOffset_;
    }

    function setTransferShortfall(uint256 transferShortfall_) external {
        transferShortfall = transferShortfall_;
    }

    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares)
    {
        shares = assets * burnMultiplier;
        _burn(owner, shares);
        ERC20(asset_).transfer(receiver, assets - transferShortfall);

        shares += returnAmountOffset;
    }

    function totalBaseAssets() external view returns (uint256) {
        return totalSupply();
    }

    function provider() external view returns (address) {
        return address(this);
    }

    function getAsset(address) external pure returns (IVault.AssetParams memory) {
        return IVault.AssetParams({index: 0, active: true, decimals: 18});
    }

    function getRate(address) external pure returns (uint256) {
        return 1 ether;
    }

    function processAccounting() external {
        processAccountingCalls++;
    }
}

contract WithdrawalAssetMock is ERC20 {
    constructor() ERC20("Asset", "AST") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract WithdrawalRequestManagerTest is Test {
    WithdrawalRequestManager manager;
    MockWithdrawAssetVault ynToken;
    WithdrawalAssetMock asset;
    Bag bagImplementation;
    BaseBeaconMaker beaconMakerImplementation;
    BaseBeaconMaker beaconMaker;

    address admin = address(0xA11CE);
    address fulfiller = address(0xF0111);
    address configurationManager = address(0xC0F16);
    address pauser = address(0xAA05E);
    address user = address(0xB0B);
    uint256 minimumAmountToLock = 1 ether;

    function setUp() public {
        ynToken = new MockWithdrawAssetVault();
        asset = new WithdrawalAssetMock();
        bagImplementation = new Bag();
        beaconMakerImplementation = new BaseBeaconMaker();
        ERC1967Proxy beaconMakerProxy = new ERC1967Proxy(
            address(beaconMakerImplementation),
            abi.encodeCall(BaseBeaconMaker.initialize, (address(bagImplementation), admin, admin, admin))
        );
        beaconMaker = BaseBeaconMaker(address(beaconMakerProxy));

        WithdrawalRequestManager implementation = new WithdrawalRequestManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                WithdrawalRequestManager.initialize,
                (
                    address(ynToken),
                    admin,
                    fulfiller,
                    configurationManager,
                    pauser,
                    address(beaconMaker),
                    minimumAmountToLock
                )
            )
        );
        manager = WithdrawalRequestManager(address(proxy));
        bytes32 creatorRole = beaconMaker.CREATOR_ROLE();
        vm.prank(admin);
        beaconMaker.grantRole(creatorRole, address(manager));

        ynToken.mint(user, 100 ether);
        asset.mint(address(ynToken), 100 ether);

        vm.prank(user);
        ynToken.approve(address(manager), type(uint256).max);
    }

    function testRequestWithdrawalTransfersTokenAndRecordsRequest() public {
        vm.expectEmit(true, true, true, false, address(manager));
        emit WithdrawalRequestManager.WithdrawalRequested(1, user, address(ynToken), address(0), 10 ether);

        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        assertEq(id, 1);
        assertEq(manager.nextRequestId(), 2);
        assertEq(address(manager.beaconMaker()), address(beaconMaker));
        assertTrue(manager.requestExists(id));
        assertFalse(manager.requestExists(id + 1));
        assertEq(ynToken.balanceOf(user), 90 ether);
        assertEq(ynToken.balanceOf(address(manager)), 10 ether);

        WithdrawalRequestManager.WithdrawalRequest memory request = manager.requests(id);
        assertEq(request.owner, user);
        assertTrue(request.bag != address(0));
        assertEq(Bag(request.bag).ownerOf(Bag(request.bag).TOKEN_ID()), user);
        assertEq(request.amountLocked, 10 ether);
    }

    function testBeaconMakerRequiresCreatorRole() public {
        bytes32 creatorRole = beaconMaker.CREATOR_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, creatorRole)
        );
        vm.prank(user);
        beaconMaker.create(abi.encodeCall(Bag.initialize, (user)));
    }

    function testBeaconMakerUpgradesImplementation() public {
        Bag newImplementation = new Bag();

        vm.prank(admin);
        beaconMaker.upgradeImplementation(address(newImplementation));

        assertEq(beaconMaker.implementation(), address(newImplementation));
    }

    function testBagClaimRequiresBagOwner() public {
        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        WithdrawalRequestManager.WithdrawalRequest memory request = manager.requests(id);
        asset.mint(request.bag, 4 ether);

        vm.expectRevert(abi.encodeWithSelector(Bag.NotBagOwner.selector, address(this)));
        Bag(request.bag).claim(address(asset), user);

        vm.prank(user);
        uint256 amountClaimed = Bag(request.bag).claim(address(asset), user);

        assertEq(amountClaimed, 4 ether);
        assertEq(asset.balanceOf(user), 4 ether);
        assertEq(asset.balanceOf(request.bag), 0);
    }

    function testRequestWithdrawalRevertsBelowMinimumAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalRequestManager.AmountBelowMinimum.selector, minimumAmountToLock - 1, minimumAmountToLock
            )
        );
        vm.prank(user);
        manager.requestWithdrawal(minimumAmountToLock - 1);
    }

    function testSetMinimumAmountToLockRequiresConfigurationManagerRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, manager.CONFIGURATION_MANAGER_ROLE()
            )
        );
        vm.prank(user);
        manager.setMinimumAmountToLock(2 ether);
    }

    function testSetMinimumAmountToLockUpdatesMinimum() public {
        vm.expectEmit(true, true, true, true, address(manager));
        emit WithdrawalRequestManager.MinimumAmountToLockUpdated(minimumAmountToLock, 2 ether);

        vm.prank(configurationManager);
        manager.setMinimumAmountToLock(2 ether);

        assertEq(manager.minimumAmountToLock(), 2 ether);
    }

    function testConvertToAssets() public view {
        assertEq(manager.convertToAssets(address(asset), 0), 0);
        assertEq(manager.convertToAssets(address(asset), 10 ether), 10 ether);
    }

    function testPausePreventsRequestWithdrawal() public {
        vm.prank(pauser);
        manager.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user);
        manager.requestWithdrawal(10 ether);
    }

    function testPauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, manager.PAUSER_ROLE()
            )
        );
        vm.prank(user);
        manager.pause();
    }

    function testFulfillWithdrawalRequestBurnsLockedTokenAndSubtractsBurnedAmount() public {
        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.expectEmit(true, true, true, true, address(manager));
        emit WithdrawalRequestManager.WithdrawalRequestFulfilled(
            id, user, address(ynToken), address(asset), 4 ether, 4 ether, 6 ether
        );

        vm.prank(fulfiller);
        uint256 amountBurned = manager.fulfillWithdrawalRequest(id, address(asset), 4 ether);

        assertEq(amountBurned, 4 ether);
        assertEq(ynToken.balanceOf(address(manager)), 6 ether);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(ynToken.processAccountingCalls(), 1);

        WithdrawalRequestManager.WithdrawalRequest memory request = manager.requests(id);
        assertEq(asset.balanceOf(request.bag), 4 ether);
        assertEq(asset.balanceOf(user), 0);
        assertEq(request.amountLocked, 6 ether);

        vm.prank(user);
        assertEq(Bag(request.bag).claim(address(asset), user), 4 ether);
        assertEq(asset.balanceOf(user), 4 ether);
        assertEq(asset.balanceOf(request.bag), 0);
    }

    function testFulfillWithdrawalRequestMaxWithdrawsMaxAssetsForLockedShares() public {
        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.expectEmit(true, true, true, true, address(manager));
        emit WithdrawalRequestManager.WithdrawalRequestFulfilled(
            id, user, address(ynToken), address(asset), 10 ether, 10 ether, 0
        );

        vm.prank(fulfiller);
        (uint256 amountBurned, uint256 assetsWithdrawn) = manager.fulfillWithdrawalRequestMax(id, address(asset));

        assertEq(amountBurned, 10 ether);
        assertEq(assetsWithdrawn, 10 ether);

        WithdrawalRequestManager.WithdrawalRequest memory request = manager.requests(id);
        assertEq(asset.balanceOf(request.bag), 10 ether);
        assertEq(asset.balanceOf(user), 0);
        assertEq(request.amountLocked, 0);

        vm.prank(user);
        assertEq(Bag(request.bag).claim(address(asset), user), 10 ether);
        assertEq(asset.balanceOf(user), 10 ether);
    }

    function testFulfillWithdrawalRequestUsesActualBalanceDeltaInsteadOfReturnValue() public {
        ynToken.setReturnAmountOffset(100 ether);

        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.prank(fulfiller);
        uint256 amountBurned = manager.fulfillWithdrawalRequest(id, address(asset), 4 ether);

        assertEq(amountBurned, 4 ether);

        WithdrawalRequestManager.WithdrawalRequest memory request = manager.requests(id);
        assertEq(request.amountLocked, 6 ether);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(request.bag), 4 ether);
        assertEq(asset.balanceOf(user), 0);
    }

    function testFulfillWithdrawalRequestRevertsWhenAssetsWithdrawnMismatchExpected() public {
        ynToken.setTransferShortfall(1 ether);

        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalRequestManager.UnexpectedAssetsWithdrawn.selector, 4 ether, 3 ether)
        );
        vm.prank(fulfiller);
        manager.fulfillWithdrawalRequest(id, address(asset), 4 ether);
    }

    function testFulfillWithdrawalRequestRequiresFulfillerRole() public {
        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, manager.FULFILLER_ROLE()
            )
        );
        vm.prank(user);
        manager.fulfillWithdrawalRequest(id, address(asset), 1 ether);
    }

    function testFulfillWithdrawalRequestRevertsWhenBurnExceedsLockedAmount() public {
        ynToken.mint(address(manager), 20 ether);
        ynToken.setBurnMultiplier(2);

        vm.prank(user);
        uint256 id = manager.requestWithdrawal(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalRequestManager.InsufficientLockedAmount.selector, id, 10 ether, 12 ether)
        );
        vm.prank(fulfiller);
        manager.fulfillWithdrawalRequest(id, address(asset), 6 ether);
    }
}
