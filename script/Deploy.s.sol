// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";
import {AsymmetricFeeHook} from "src/hooks/AsymmetricFeeHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MinimalAccountEIP7702} from "test/mocks/accounts/MinimalAccountEIP7702.sol";
import {Permit2} from "permit2/Permit2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {TestingUtils} from "test/helpers/TestingUtils.sol";

import {Script, console} from "forge-std/Script.sol";

contract Deploy is Script, Deployers, TestingUtils {
    using LiquidityAmounts for uint160;

    // Contract instances
    EntryPoint public entryPoint;
    Permit2 public permit2;
    UniswapPaymaster public paymaster;
    ERC20Mock public token;
    MinimalAccountEIP7702 public account;
    AsymmetricFeeHook public hook;

    // Addresses
    address public bundler;
    address public depositor;
    address public lp1;
    address public lp2;
    address public EOA;
    uint256 public EOAPrivateKey;
    address public receiver;

    // Constants

    function run() public {
        vm.startBroadcast();
        
        // deploy the entrypoint
        deployCodeTo(
            "EntryPoint",
            address(ERC4337Utils.ENTRYPOINT_V08)
        );
        entryPoint = EntryPoint(payable(address(ERC4337Utils.ENTRYPOINT_V08)));
        console.log("EntryPoint: ", address(entryPoint));

        // deploy uniswap interface
        manager = new PoolManager(address(0));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        console.log("Manager: ", address(manager));

        // deploy Permit2
        permit2 = new Permit2();
        console.log("Permit2: ", address(permit2));

        // deploy the paymaster
        paymaster = new UniswapPaymaster(manager, permit2);
        console.log("Paymaster: ", address(paymaster));

        // create a ERC20
        token = new ERC20Mock();
        console.log("Token: ", address(token));

        // Deploy the ECDSA account to delegate to
        account = new MinimalAccountEIP7702();
        console.log("Account: ", address(account));
        
        vm.stopBroadcast();

        // // deploy the asymmetric fee hook
        // hook = AsymmetricFeeHook(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        // deployCodeTo(
        //     "AsymmetricFeeHook", address(hook)
        // );
        // console.log("Hook: ", address(hook));

        // // initialize the pool
        (key,) = initPool(
            Currency.wrap(address(0)), // native currency
            Currency.wrap(address(token)), // token currency
            IHooks(address(0)), // hooks
            100, // fee
            60, // tick spacing
            SQRT_PRICE_1_1 // sqrt price x96
        );
        console.log("Pool Key: ");
        console.logBytes32(PoolId.unwrap(key.toId()));

        // create accounts
        (bundler) = makeAddr("bundler");
        (depositor) = makeAddr("depositor");
        (lp1) = makeAddr("lp1");
        (lp2) = makeAddr("lp2");
        
        // Use Foundry's default first account (same as Anvil's first account)
        EOA = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        EOAPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        
        (receiver) = makeAddr("receiver");

        console.log("Bundler: ", bundler);
        console.log("Depositor: ", depositor);
        console.log("LP1: ", lp1);
        console.log("LP2: ", lp2);
        console.log("EOA (Foundry default): ", EOA);
        console.log("EOA Private Key (hex): 0x%x", EOAPrivateKey);
        console.log("Receiver: ", receiver);

        // burn all the eth from the EOA
        vm.deal(EOA, 0);

        // fund bundler
        vm.deal(bundler, 1e18);

        // fund depositor
        vm.deal(depositor, 1e18);

        // give eth to lps
        vm.deal(lp1, 1e26);
        vm.deal(lp2, 1e26);

        // give token to lps
        token.mint(lp1, 1e26);
        token.mint(lp2, 1e26);

        // add a big amount of liquidity
        uint128 liquidityToAdd = 1e22;

        // get eth amounts for 1e18 liquidity
        (uint256 ethAmount,) =
            getAmountsForLiquidity(manager, key, liquidityToAdd, _getTickLower(), _getTickUpper());
        uint256 ethAmountPlusBuffer = ethAmount * 110 / 100; // 10% buffer, rest is refunded by the swap router

        // lp1 adds 1e18 liquidity
        vm.startPrank(lp1);
        token.approve(address(manager), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmountPlusBuffer}(
            key, _liquidityParams(int128(liquidityToAdd)), ""
        );
        vm.stopPrank();

        // lp2 adds 1e18 liquidity
        vm.startPrank(lp2);
        token.approve(address(manager), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmountPlusBuffer}(
            key, _liquidityParams(int128(liquidityToAdd)), ""
        );
        vm.stopPrank();
    }

    /**
     * @dev Deploys a contract and returns its address
     * @param contractName Name of the contract
     * @return deployedAddress Address of the deployed contract
     */
    function deployCode(string memory contractName) internal override returns (address deployedAddress) {
        bytes memory bytecode = vm.getCode(contractName);
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployedAddress != address(0), "Deployment failed");
    }
}
