// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {MainnetActors as Actors} from "lib/yieldnest-vault/script/Actors.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {SetupVault, Vault, WETH9} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {PermissionedVaultHook} from "test/testhooks/PermissionedVaultHook.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {FeeHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {SetupBase6DecimalsVault} from "lib/yieldnest-vault/test/unit/vault/base6decimals/SetupBase6DecimalsVault.sol";

contract BaseIntegrationTest_base_6decimals is Test, Actors {
    Vault public vault;
    WETH9 public weth;

    MetaHooks public metaHooks;
    PermissionedVaultHook public permissionedVaultHook;
    ProcessAccountingGuardHook public processAccountingGuardHook;
    FeeHooks public feeHooks;

    address public constant owner = address(111222333);

    address public constant HOOK_MANAGER = 0x1234567890123456789012345678911234567891;
    address public constant depositor = address(0xbeefe1);

    function setUp() public virtual {
        SetupBase6DecimalsVault setup = new SetupBase6DecimalsVault();
        (vault, weth) = setup.setup();

        // address vault_, address defaultAdmin, address hookManager)
        metaHooks = new MetaHooks(address(vault), ADMIN, HOOK_MANAGER);

        // Create individual hooks
        address[] memory whitelistedUsers = new address[](1);
        whitelistedUsers[0] = depositor;
        permissionedVaultHook = new PermissionedVaultHook(address(metaHooks), owner, whitelistedUsers);

        FeeHooks previousFeeHooks = FeeHooks(address(vault.hooks()));
        feeHooks = new FeeHooks(
            address(metaHooks),
            owner,
            previousFeeHooks.performanceFee(), // performanceFee (0.1%)
            previousFeeHooks.performanceFeeRecipient(),
            previousFeeHooks.getConfig()
        );

        processAccountingGuardHook = new ProcessAccountingGuardHook(
            address(metaHooks),
            owner,
            0.001 ether, // maxDecreaseRatio (0.1%)
            0.002 ether, // maxIncreaseRatio (0.2%)
            0.0015 ether, // maxTotalSupplyIncreaseRatio (0.15%)
            previousFeeHooks.performanceFee()
        );

        // Set up hooks array for MetaHooks
        IHooks[] memory hooks = new IHooks[](3);
        hooks[0] = IHooks(address(permissionedVaultHook));
        hooks[1] = IHooks(address(feeHooks));
        hooks[2] = IHooks(address(processAccountingGuardHook));

        vm.startPrank(HOOK_MANAGER);
        metaHooks.setHooks(hooks);
        vm.stopPrank();

        vm.startPrank(HOOKS_MANAGER);
        vault.setHooks(address(metaHooks));
        vm.stopPrank();

        vm.startPrank(ADMIN);
        vault.setBaseWithdrawalFee(1e5); // 0.1% (1e5 / 1e8)
        vm.stopPrank();
    }
}
