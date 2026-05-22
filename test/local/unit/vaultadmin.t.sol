// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {VaultManager} from "src/admin/VaultManager.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IValidator.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {MockStrategy} from "lib/yieldnest-vault/test/unit/mocks/MockStrategy.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LocalWETH9 {
    string public constant name = "Wrapped Ether";
    string public constant symbol = "WETH";
    uint8 public constant decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "insufficient balance");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad, "insufficient balance");

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "insufficient allowance");
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}

contract LocalProvider is IProvider {
    mapping(address => uint256) public rates;

    function setRate(address asset_, uint256 rate_) external {
        rates[asset_] = rate_;
    }

    function getRate(address asset_) external view returns (uint256) {
        return rates[asset_];
    }
}

contract LocalToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract LocalERC4626Asset is ERC20, ERC4626 {
    bool public revertOnMaxWithdraw;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) {}

    function decimals() public pure override(ERC20, ERC4626) returns (uint8) {
        return 18;
    }

    function setRevertOnMaxWithdraw(bool shouldRevert_) external {
        revertOnMaxWithdraw = shouldRevert_;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (revertOnMaxWithdraw) revert("maxWithdraw failed");
        return super.maxWithdraw(owner);
    }
}

contract LocalNoopTarget {
    function ping(uint256 value) external pure returns (uint256) {
        return value + 1;
    }
}

abstract contract LocalHooksBase is IHooks {
    string internal _hookName;
    Config internal _config;
    IVault public immutable VAULT;

    constructor(address vault_, string memory hookName_, Config memory config_) {
        VAULT = IVault(vault_);
        _hookName = hookName_;
        _config = config_;
    }

    function name() external view override returns (string memory) {
        return _hookName;
    }

    function setConfig(Config memory config_) external override {
        _config = config_;
    }

    function getConfig() external view override returns (Config memory) {
        return _config;
    }

    function beforeDeposit(DepositParams memory) external virtual override {}
    function afterDeposit(DepositParams memory) external virtual override {}
    function beforeMint(MintParams memory) external virtual override {}
    function afterMint(MintParams memory) external virtual override {}
    function beforeRedeem(RedeemParams memory) external virtual override {}
    function afterRedeem(RedeemParams memory) external virtual override {}
    function beforeWithdraw(WithdrawParams memory) external virtual override {}
    function afterWithdraw(WithdrawParams memory) external virtual override {}
    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external virtual override {}
    function afterProcessAccounting(AfterProcessAccountingParams memory) external virtual override {}
}

contract LocalNoopHooks is LocalHooksBase {
    constructor(address vault_)
        LocalHooksBase(
            vault_,
            "LocalNoopHooks",
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        )
    {}
}

contract LocalBeforeAccountingTransferHook is LocalHooksBase {
    IERC20 public immutable token;
    uint256 public immutable amount;

    constructor(address vault_, address token_, uint256 amount_)
        LocalHooksBase(
            vault_,
            "LocalBeforeAccountingTransferHook",
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: true,
                afterProcessAccounting: false
            })
        )
    {
        token = IERC20(token_);
        amount = amount_;
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external override {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        token.transfer(address(VAULT), amount);
    }
}

contract LocalAfterAccountingMintHook is LocalHooksBase {
    address public immutable recipient;
    uint256 public immutable sharesToMint;
    uint256 public immutable mintOnCallNumber;
    uint256 public callCount;

    constructor(address vault_, address recipient_, uint256 sharesToMint_, uint256 mintOnCallNumber_)
        LocalHooksBase(
            vault_,
            "LocalAfterAccountingMintHook",
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: true
            })
        )
    {
        recipient = recipient_;
        sharesToMint = sharesToMint_;
        mintOnCallNumber = mintOnCallNumber_;
    }

    function afterProcessAccounting(AfterProcessAccountingParams memory) external override {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        callCount += 1;
        if (callCount == mintOnCallNumber) {
            VAULT.mintShares(recipient, sharesToMint);
        }
    }
}

contract VaultManagerUnitTest is Test {
    VaultManager internal vaultManager;
    Vault internal vault;
    LocalWETH9 internal weth;
    LocalProvider internal provider;
    LocalProvider internal newProvider;
    LocalERC4626Asset internal bufferAsset;
    LocalERC4626Asset internal syntheticAsset1;
    LocalERC4626Asset internal syntheticAsset2;
    LocalNoopTarget internal noopTarget;

    address internal admin = address(0xA1);
    address internal bufferManagerRole = address(0xB1);
    address internal providerManagerRole = address(0xC1);
    address internal assetAdderRole = address(0xD1);
    address internal assetDeleterRole = address(0xE1);
    address internal assetWithdrawerRole = address(0xF1);
    address internal totalAssetsModeManagerRole = address(0xF2);
    address internal hooksManagerRole = address(0xF3);
    address internal processorRole = address(0xF4);
    address internal alice = address(0xAA);
    address internal sink = address(0xBB);

    function setUp() public {
        weth = new LocalWETH9();
        provider = new LocalProvider();
        newProvider = new LocalProvider();
        bufferAsset = new LocalERC4626Asset(IERC20(address(weth)), "Buffer Asset", "BUF");
        syntheticAsset1 = new LocalERC4626Asset(IERC20(address(weth)), "Synthetic Asset 1", "SYN1");
        syntheticAsset2 = new LocalERC4626Asset(IERC20(address(weth)), "Synthetic Asset 2", "SYN2");
        noopTarget = new LocalNoopTarget();

        _setProviderRates(provider);
        _setProviderRates(newProvider);

        vault = _deployVault(0);
        vaultManager = _deployVaultManager(address(vault));

        vm.startPrank(admin);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.grantRole(vault.UNPAUSER_ROLE(), admin);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), admin);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), admin);

        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(vaultManager));
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), address(vaultManager));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(vaultManager));
        vault.grantRole(vault.PROCESSOR_ROLE(), address(vaultManager));
        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), address(vaultManager));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(vaultManager));

        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(this));

        vault.setProvider(address(provider));
        vault.addAsset(address(weth), true);
        vault.addAsset(address(bufferAsset), true);
        vault.addAsset(address(syntheticAsset1), true);
        vault.addAsset(address(syntheticAsset2), true);
        vault.unpause();
        vm.stopPrank();

        _setNoopRule(noopTarget);
        _setTransferRule(address(weth), sink);
    }

    function testSetCurrentBuffer() public {
        vm.startPrank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(bufferAsset));
        assertEq(vault.buffer(), address(bufferAsset));

        address nonAsset = address(new LocalERC4626Asset(IERC20(address(weth)), "External", "EXT"));
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotVaultAsset.selector, nonAsset));
        vaultManager.setCurrentBuffer(nonAsset);

        LocalERC4626Asset wrongUnderlying =
            new LocalERC4626Asset(IERC20(address(new LocalToken("Other", "OTH"))), "Wrong", "WRONG");
        vm.expectRevert(abi.encodeWithSelector(VaultManager.ERC4626AssetMismatch.selector, address(wrongUnderlying)));
        vaultManager.setCurrentBuffer(address(wrongUnderlying), true);
        vm.stopPrank();
    }

    function testSetCurrentBufferSkipIsAssetCheck() public {
        LocalERC4626Asset externalBuffer = new LocalERC4626Asset(IERC20(address(weth)), "External", "EXT");

        vm.prank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(externalBuffer), true);

        assertEq(vault.buffer(), address(externalBuffer));
    }

    function testSetCurrentBufferRevertsWhenMaxWithdrawProbeFails() public {
        bufferAsset.setRevertOnMaxWithdraw(true);

        vm.prank(bufferManagerRole);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.BufferMaxWithdrawCheckFailed.selector, address(bufferAsset))
        );
        vaultManager.setCurrentBuffer(address(bufferAsset));
    }

    function testRolesAreDecoupledPerOperation() public {
        vm.prank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(bufferAsset));
        assertEq(vault.buffer(), address(bufferAsset));

        vm.prank(providerManagerRole);
        vaultManager.setProvider(address(provider));
        assertEq(vault.provider(), address(provider));

        LocalERC4626Asset addedAsset = new LocalERC4626Asset(IERC20(address(weth)), "Added Asset", "ADDED");
        provider.setRate(address(addedAsset), 1e18);
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](1);
        assetsToAdd[0] = address(addedAsset);
        activeFlags[0] = true;

        vm.prank(assetAdderRole);
        vaultManager.addAssets(assetsToAdd, activeFlags);
        assertTrue(vault.hasAsset(address(addedAsset)));

        vm.prank(assetDeleterRole);
        vaultManager.deleteAsset(address(addedAsset));
        assertFalse(vault.hasAsset(address(addedAsset)));

        _depositSyntheticAsset(syntheticAsset1, alice, 10 ether);
        _approveManagerShares(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(assetWithdrawerRole);
        uint256 burnedShares = vaultManager.withdrawAsset(address(syntheticAsset1), 5 ether, alice);
        assertGt(burnedShares, 0);
        assertLt(vault.balanceOf(alice), aliceSharesBefore);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(noopTarget);
        data[0] = abi.encodeWithSignature("ping(uint256)", 41);

        vm.prank(processorRole);
        bytes[] memory results = vaultManager.processor(targets, values, data);
        assertEq(results.length, 1);
        assertEq(abi.decode(results[0], (uint256)), 42);

        vm.prank(bufferManagerRole);
        vm.expectRevert();
        vaultManager.setProvider(address(provider));

        vm.prank(providerManagerRole);
        vm.expectRevert();
        vaultManager.addAssets(assetsToAdd, activeFlags);

        vm.prank(assetAdderRole);
        vm.expectRevert();
        vaultManager.deleteAsset(address(syntheticAsset1));

        vm.prank(assetDeleterRole);
        vm.expectRevert();
        vaultManager.processor(targets, values, data);

        vm.prank(processorRole);
        vm.expectRevert();
        vaultManager.withdrawAsset(address(syntheticAsset1), 1 ether, alice);
    }

    function testSetProviderSyncsAccountingBeforeComparingTotals() public {
        _mintWeth(address(this), 10 ether);
        weth.transfer(address(vault), 10 ether);
        assertEq(vault.totalBaseAssets(), 0);
        assertEq(vault.computeTotalAssets(), 10 ether);

        vm.prank(providerManagerRole);
        vaultManager.setProvider(address(newProvider));

        assertEq(vault.provider(), address(newProvider));
        assertEq(vault.totalBaseAssets(), 10 ether);
    }

    function testSetProviderRevertsWhenBaseAssetRateChanges() public {
        newProvider.setRate(address(weth), 2e18);

        vm.prank(providerManagerRole);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.AssetRateChanged.selector, address(weth), 1e18, 2e18)
        );
        vaultManager.setProvider(address(newProvider));
    }

    function testSetProviderRevertsWhenDefaultAssetRateChangesOnDistinctDefaultVault() public {
        LocalWETH9 altWeth = new LocalWETH9();
        LocalERC4626Asset altBaseAsset = new LocalERC4626Asset(IERC20(address(altWeth)), "Base Asset", "BASE");
        LocalProvider altProvider = new LocalProvider();
        LocalProvider altNewProvider = new LocalProvider();
        altProvider.setRate(address(altBaseAsset), 1e18);
        altProvider.setRate(address(altWeth), 1e18);
        altNewProvider.setRate(address(altBaseAsset), 1e18);
        altNewProvider.setRate(address(altWeth), 2e18);

        Vault altVault = _deployVault(1);
        VaultManager altManager = _deployVaultManager(address(altVault));

        vm.startPrank(admin);
        altVault.grantRole(altVault.PROVIDER_MANAGER_ROLE(), admin);
        altVault.grantRole(altVault.ASSET_MANAGER_ROLE(), admin);
        altVault.grantRole(altVault.UNPAUSER_ROLE(), admin);
        altVault.grantRole(altVault.PROVIDER_MANAGER_ROLE(), address(altManager));
        altVault.grantRole(altVault.ASSET_MANAGER_ROLE(), address(altManager));
        altVault.setProvider(address(altProvider));
        altVault.addAsset(address(altBaseAsset), true);
        altVault.addAsset(address(altWeth), true);
        altVault.unpause();
        vm.stopPrank();

        vm.prank(providerManagerRole);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.AssetRateChanged.selector, address(altWeth), 1e18, 2e18)
        );
        altManager.setProvider(address(altNewProvider));
    }

    function testDeleteAssetRevertsForBuffer() public {
        vm.prank(bufferManagerRole);
        vaultManager.setCurrentBuffer(address(bufferAsset));

        vm.prank(assetDeleterRole);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.CannotDeleteBufferAsset.selector, address(bufferAsset))
        );
        vaultManager.deleteAsset(address(bufferAsset));
    }

    function testDeleteAssetsRevertsForDuplicates() public {
        address[] memory assetsToDelete = new address[](2);
        assetsToDelete[0] = address(syntheticAsset1);
        assetsToDelete[1] = address(syntheticAsset1);

        vm.prank(assetDeleterRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.DuplicateAsset.selector, address(syntheticAsset1)));
        vaultManager.deleteAssets(assetsToDelete);
    }

    function testAddAssetsRevertsOnLengthMismatch() public {
        address[] memory assetsToAdd = new address[](1);
        bool[] memory activeFlags = new bool[](0);
        assetsToAdd[0] = address(new LocalERC4626Asset(IERC20(address(weth)), "New", "NEW"));

        vm.prank(assetAdderRole);
        vm.expectRevert(VaultManager.LengthMismatch.selector);
        vaultManager.addAssets(assetsToAdd, activeFlags);
    }

    function testProcessorRevertsOnLengthMismatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](0);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(noopTarget);
        data[0] = abi.encodeWithSignature("ping(uint256)", 1);

        vm.prank(processorRole);
        vm.expectRevert(VaultManager.LengthMismatch.selector);
        vaultManager.processor(targets, values, data);
    }

    function testSetMaxProcessorDeltaRatios() public {
        vm.prank(admin);
        vaultManager.setMaxProcessorBaseAssetsDeltaRatio(0.05e18);
        vm.prank(admin);
        vaultManager.setMaxProcessorSupplyDeltaRatio(0.06e18);

        assertEq(vaultManager.maxProcessorBaseAssetsDeltaRatio(), 0.05e18);
        assertEq(vaultManager.maxProcessorSupplyDeltaRatio(), 0.06e18);
    }

    function testSetMaxProcessorBaseAssetsDeltaRatioRevertsAboveDenominator() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.RatioTooHigh.selector, 1e18 + 1));
        vaultManager.setMaxProcessorBaseAssetsDeltaRatio(1e18 + 1);
    }

    function testSetMaxProcessorSupplyDeltaRatioRevertsAboveDenominator() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.RatioTooHigh.selector, 1e18 + 1));
        vaultManager.setMaxProcessorSupplyDeltaRatio(1e18 + 1);
    }

    function testProcessorRevertsWhenTotalAssetsDeltaExceeded() public {
        _depositWethIntoVault(alice, 100 ether);

        vm.prank(admin);
        vaultManager.setMaxProcessorBaseAssetsDeltaRatio(0.05e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(weth);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", sink, 7 ether);

        vm.prank(processorRole);
        vm.expectRevert(
            abi.encodeWithSelector(VaultManager.TotalBaseAssetsDeltaExceeded.selector, 100 ether, 93 ether)
        );
        vaultManager.processor(targets, values, data);
    }

    function testProcessorRevertsWhenTotalSupplyDeltaExceeded() public {
        _depositWethIntoVault(alice, 100 ether);

        LocalAfterAccountingMintHook mintHook = new LocalAfterAccountingMintHook(address(vault), alice, 7 ether, 2);
        vm.prank(admin);
        vault.setHooks(address(mintHook));

        vm.prank(admin);
        vaultManager.setMaxProcessorSupplyDeltaRatio(0.05e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(noopTarget);
        data[0] = abi.encodeWithSignature("ping(uint256)", 1);

        vm.prank(processorRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.TotalSupplyDeltaExceeded.selector, 100 ether, 107 ether));
        vaultManager.processor(targets, values, data);
    }

    function testProcessorAllowsConfiguredDeltaForAssetsAndSupply() public {
        _depositWethIntoVault(alice, 100 ether);

        vm.prank(admin);
        vaultManager.setMaxProcessorBaseAssetsDeltaRatio(0.05e18);
        vm.prank(admin);
        vaultManager.setMaxProcessorSupplyDeltaRatio(0.05e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(weth);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", sink, 5 ether);

        vm.prank(processorRole);
        bytes[] memory results = vaultManager.processor(targets, values, data);

        assertEq(vault.totalBaseAssets(), 95 ether);
        assertEq(vault.totalAssets(), 95 ether);
        assertEq(vault.totalSupply(), 100 ether);
        assertEq(results.length, 1);
        assertEq(abi.decode(results[0], (bool)), true);
        assertEq(weth.balanceOf(sink), 5 ether);
    }

    function testSetAlwaysComputeTotalAssets() public {
        _mintWeth(address(this), 10 ether);
        weth.transfer(address(vault), 10 ether);

        vm.prank(totalAssetsModeManagerRole);
        vaultManager.setAlwaysComputeTotalAssets(true);

        assertTrue(vault.alwaysComputeTotalAssets());
        assertEq(vault.totalBaseAssets(), 10 ether);
    }

    function testSetAlwaysComputeTotalAssetsDisablesWithoutChangingVisibleTotals() public {
        _mintWeth(address(this), 10 ether);
        weth.transfer(address(vault), 10 ether);

        vm.prank(totalAssetsModeManagerRole);
        vaultManager.setAlwaysComputeTotalAssets(true);
        assertEq(vault.totalBaseAssets(), 10 ether);

        vm.prank(totalAssetsModeManagerRole);
        vaultManager.setAlwaysComputeTotalAssets(false);

        assertFalse(vault.alwaysComputeTotalAssets());
        assertEq(vault.totalBaseAssets(), 10 ether);
        assertEq(vault.totalAssets(), 10 ether);
    }

    function testSetAlwaysComputeTotalAssetsRevertsWhenHooksAreConfigured() public {
        vault.setHooks(address(new LocalNoopHooks(address(vault))));

        vm.prank(totalAssetsModeManagerRole);
        vm.expectRevert(VaultManager.HooksMustBeDisabled.selector);
        vaultManager.setAlwaysComputeTotalAssets(true);
    }

    function testSetHooks() public {
        LocalNoopHooks hook = new LocalNoopHooks(address(vault));

        vm.prank(hooksManagerRole);
        vaultManager.setHooks(address(hook));

        assertEq(address(vault.hooks()), address(hook));
    }

    function testSetHooksRevertsWhenAlwaysComputeTotalAssetsEnabled() public {
        vm.prank(totalAssetsModeManagerRole);
        vaultManager.setAlwaysComputeTotalAssets(true);
        assertTrue(vault.alwaysComputeTotalAssets());
        LocalNoopHooks hook = new LocalNoopHooks(address(vault));

        vm.prank(hooksManagerRole);
        vm.expectRevert(VaultManager.AlwaysComputeTotalAssetsMustBeDisabled.selector);
        vaultManager.setHooks(address(hook));
    }

    function testSetHooksRevertsOnTotalBaseAssetsMismatch() public {
        LocalBeforeAccountingTransferHook hook =
            new LocalBeforeAccountingTransferHook(address(vault), address(weth), 1 ether);
        _mintWeth(address(this), 1 ether);
        weth.transfer(address(hook), 1 ether);

        vm.prank(hooksManagerRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.TotalBaseAssetsMismatch.selector, 0, 1 ether));
        vaultManager.setHooks(address(hook));
    }

    function testSetHooksRevertsOnTotalSupplyMismatch() public {
        LocalAfterAccountingMintHook hook = new LocalAfterAccountingMintHook(address(vault), alice, 1 ether, 1);

        vm.prank(hooksManagerRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.TotalSupplyMismatch.selector, 0, 1 ether));
        vaultManager.setHooks(address(hook));
    }

    function testWithdrawAssetUsesReceiverAsOwnerAndProcessesAccounting() public {
        _depositSyntheticAsset(syntheticAsset1, alice, 7 ether);
        _approveManagerShares(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(assetWithdrawerRole);
        uint256 burnedShares = vaultManager.withdrawAsset(address(syntheticAsset1), 5 ether, alice);

        assertGt(burnedShares, 0);
        assertEq(syntheticAsset1.balanceOf(alice), 5 ether);
        assertLt(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(vault.totalBaseAssets(), 2 ether);
    }

    function testWithdrawAssetWithExplicitOwnerProcessesAccounting() public {
        _depositSyntheticAsset(syntheticAsset2, alice, 9 ether);
        _approveManagerShares(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(assetWithdrawerRole);
        uint256 burnedShares = vaultManager.withdrawAsset(address(syntheticAsset2), 6 ether, sink, alice);

        assertGt(burnedShares, 0);
        assertEq(syntheticAsset2.balanceOf(sink), 6 ether);
        assertLt(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(vault.totalBaseAssets(), 3 ether);
    }

    function testSetAssetWithdrawableRevertsForNonStrategyManager() public {
        vm.prank(assetAdderRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.ManagedContractNotStrategy.selector, address(vault)));
        vaultManager.setAssetWithdrawable(address(weth), true);
    }

    function _deployVault(uint256 defaultAssetIndex_) internal returns (Vault deployedVault) {
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), admin, "");
        deployedVault = Vault(payable(address(proxy)));

        vm.prank(admin);
        deployedVault.initialize(admin, "Local Vault", "LVLT", 18, 0, false, false, defaultAssetIndex_);
    }

    function _deployVaultManager(address vault_) internal returns (VaultManager manager) {
        VaultManager implementation = new VaultManager();
        bytes memory initData = abi.encodeCall(
            VaultManager.initialize,
            (
                vault_,
                admin,
                bufferManagerRole,
                providerManagerRole,
                assetAdderRole,
                assetDeleterRole,
                assetWithdrawerRole,
                totalAssetsModeManagerRole,
                hooksManagerRole,
                processorRole
            )
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), admin, initData);
        manager = VaultManager(address(proxy));
    }

    function _setProviderRates(LocalProvider provider_) internal {
        provider_.setRate(address(weth), 1e18);
        provider_.setRate(address(bufferAsset), 1e18);
        provider_.setRate(address(syntheticAsset1), 1e18);
        provider_.setRate(address(syntheticAsset2), 1e18);
    }

    function _setNoopRule(LocalNoopTarget target) internal {
        bytes4 functionSig = bytes4(keccak256("ping(uint256)"));
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault.setProcessorRule(address(target), functionSig, rule);
    }

    function _setTransferRule(address token, address recipient) internal {
        bytes4 functionSig = bytes4(keccak256("transfer(address,uint256)"));
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = recipient;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault.setProcessorRule(token, functionSig, rule);
    }

    function _mintWeth(address account, uint256 amount) internal {
        vm.deal(account, amount);
        vm.prank(account);
        weth.deposit{value: amount}();
    }

    function _depositWethIntoVault(address depositor, uint256 amount) internal {
        _mintWeth(depositor, amount);
        vm.startPrank(depositor);
        weth.approve(address(vault), amount);
        vault.deposit(amount, depositor);
        vm.stopPrank();
    }

    function _depositSyntheticAsset(LocalERC4626Asset asset_, address depositor, uint256 amount) internal {
        _mintWeth(depositor, amount);

        vm.startPrank(depositor);
        weth.approve(address(asset_), amount);
        asset_.deposit(amount, depositor);
        asset_.approve(address(vault), amount);
        vault.depositAsset(address(asset_), amount, depositor);
        vm.stopPrank();
    }

    function _approveManagerShares(address owner) internal {
        vm.prank(owner);
        vault.approve(address(vaultManager), type(uint256).max);
    }
}

contract VaultManagerStrategyUnitTest is Test {
    VaultManager internal vaultManager;
    MockStrategy internal strategy;
    LocalWETH9 internal weth;
    LocalProvider internal provider;

    address internal admin = address(0xA1);
    address internal assetAdderRole = address(0xD1);

    function setUp() public {
        weth = new LocalWETH9();
        provider = new LocalProvider();
        provider.setRate(address(weth), 1e18);

        MockStrategy strategyImplementation = new MockStrategy();
        TransparentUpgradeableProxy strategyProxy =
            new TransparentUpgradeableProxy(address(strategyImplementation), admin, "");
        strategy = MockStrategy(payable(address(strategyProxy)));

        vm.startPrank(admin);
        strategy.initialize("Mock Strategy", "MS", admin, true, 0);
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), admin);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), admin);
        strategy.setProvider(address(provider));
        strategy.addAsset(address(weth), true);
        strategy.setAssetWithdrawable(address(weth), true);
        vm.stopPrank();

        VaultManager managerImplementation = new VaultManager();
        bytes memory initData = abi.encodeCall(
            VaultManager.initialize,
            (
                address(strategy),
                admin,
                admin,
                admin,
                assetAdderRole,
                admin,
                admin,
                admin,
                admin,
                admin
            )
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(managerImplementation), admin, initData);
        vaultManager = VaultManager(address(proxy));

        vm.startPrank(admin);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), address(vaultManager));
        vm.stopPrank();
    }

    function testSetAssetWithdrawableForExistingAsset() public {
        address strategyAsset = address(strategy.asset());

        assertTrue(vaultManager.isStrategyManaged(), "manager should detect strategy target");
        assertTrue(strategy.getAssetWithdrawable(strategyAsset), "default strategy asset should start true");

        vm.prank(assetAdderRole);
        vaultManager.setAssetWithdrawable(strategyAsset, false);

        assertFalse(strategy.getAssetWithdrawable(strategyAsset), "withdrawable should be updated");
    }

    function testSetAssetWithdrawableRevertsForUnknownAsset() public {
        address unknownAsset = address(0x1234);

        vm.prank(assetAdderRole);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotVaultAsset.selector, unknownAsset));
        vaultManager.setAssetWithdrawable(unknownAsset, true);
    }
}
