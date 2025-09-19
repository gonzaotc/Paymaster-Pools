// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TestingUtils} from "test/helpers/TestingUtils.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract AddLiquidity is Script, TestingUtils {
    function run() public {
        ERC20Mock token = ERC20Mock(vm.envAddress("TOKEN_ADDRESS"));
        PoolManager manager = PoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
        PoolModifyLiquidityTest modifyLiquidityRouter =
            PoolModifyLiquidityTest(vm.envAddress("MODIFY_LIQUIDITY_ROUTER_ADDRESS"));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(vm.envAddress("CURRENCY0_ADDRESS")),
            currency1: Currency.wrap(vm.envAddress("CURRENCY1_ADDRESS")),
            fee: uint24(vm.envUint("FEE")),
            tickSpacing: int24(int256(vm.envUint("TICK_SPACING"))),
            hooks: IHooks(address(0))
        });
        
        uint256 lp1PrivateKey = vm.envUint("LP1_PRIVATE_KEY");

        vm.startBroadcast(lp1PrivateKey);

         // add 1e28 liquidity
        uint128 liquidityToAdd = 1e15;

        // get eth amounts for 1e18 liquidity
        (uint256 ethAmount,) =
            getAmountsForLiquidity(manager, key, liquidityToAdd, _getTickLower(), _getTickUpper());
        uint256 ethAmountPlusBuffer = ethAmount * 110 / 100; // 10% buffer, rest is refunded by the swap router


        token.approve(address(manager), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmountPlusBuffer}(
            key, _liquidityParams(int128(liquidityToAdd)), ""
        );
        vm.stopBroadcast();
    }
}
