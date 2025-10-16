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

contract BaseMainnetIntegrationTest is Test, Actors {
    Vault public vault;
    WETH9 public weth;

    MetaHooks public metaHooks;
    PermissionedVaultHook public permissionedVaultHook;
    ProcessAccountingGuardHook public processAccountingGuardHook;
    FeeHooks public feeHooks;

    address public constant owner = address(111222333);

    address public constant depositor = address(0xbeefe1);

    address public constant feeReceiver = address(0xbeefe277);

    function setUp() public virtual {
        vault = Vault(payable(MC.YNETHX));
        weth = WETH9(payable(MC.WETH));

        vm.startPrank(ADMIN);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), HOOKS_MANAGER);
        vm.stopPrank();

        // address vault_, address defaultAdmin, address hookManager)
        metaHooks = new MetaHooks(address(vault), ADMIN, HOOKS_MANAGER);

        // Create individual hooks
        address[] memory whitelistedUsers = new address[](1);
        whitelistedUsers[0] = depositor;
        permissionedVaultHook = new PermissionedVaultHook(address(metaHooks), owner, whitelistedUsers);

        uint256 performanceFee = 0.001 ether;
        feeHooks = new FeeHooks(
            address(metaHooks),
            owner,
            performanceFee, // performanceFee (0.1%)
            feeReceiver,
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
        );

        processAccountingGuardHook = new ProcessAccountingGuardHook(
            address(metaHooks),
            owner,
            0.001 ether, // maxDecreaseRatio (0.1%)
            0.002 ether, // maxIncreaseRatio (0.2%)
            0.0015 ether, // maxTotalSupplyIncreaseRatio (0.15%)
            performanceFee
        );

        vault.processAccounting();

        // Set up hooks array for MetaHooks
        IHooks[] memory hooks = new IHooks[](3);
        hooks[0] = IHooks(address(permissionedVaultHook));
        hooks[1] = IHooks(address(feeHooks));
        hooks[2] = IHooks(address(processAccountingGuardHook));

        vm.startPrank(HOOKS_MANAGER);
        metaHooks.setHooks(hooks);
        vm.stopPrank();

        vm.startPrank(HOOKS_MANAGER);
        vault.setHooks(address(metaHooks));
        vm.stopPrank();
    }
}
