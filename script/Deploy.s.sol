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
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

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
    uint256 public bundlerPrivateKey;
    address public depositor;
    uint256 public depositorPrivateKey;
    address public lp1;
    uint256 public lp1PrivateKey;
    address public lp2;
    uint256 public lp2PrivateKey;
    address public EOA;
    uint256 public EOAPrivateKey;
    address public receiver;

    // Constants

    function run() public {
        vm.startBroadcast();

        // get the entrypoint
        entryPoint = EntryPoint(payable(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108));

        // get the uniswap interface
        manager = PoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        permit2 = Permit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // deploy the paymaster
        paymaster = new UniswapPaymaster(manager, permit2);

        // create a ERC20
        token = new ERC20Mock();
        console.log("Token: ", address(token));

        // Deploy the ECDSA account to delegate to
        account = new MinimalAccountEIP7702();

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
        (bundler, bundlerPrivateKey) = makeAddrAndKey("bundler");
        (depositor, depositorPrivateKey) = makeAddrAndKey("depositor");
        (lp1, lp1PrivateKey) = makeAddrAndKey("lp1");
        (lp2, lp2PrivateKey) = makeAddrAndKey("lp2");

        // get the EOA
        EOA = vm.envAddress("EOA_ADDRESS");
        EOAPrivateKey = vm.envUint("EOA_PRIVATE_KEY");

        // deal eth to EOA
        vm.deal(EOA, 1e18);

        (receiver) = makeAddr("receiver");

        console.log("EntryPoint: ", address(entryPoint));
        console.log("Permit2: ", address(permit2));
        console.log("Paymaster: ", address(paymaster));
        console.log("Token: ", address(token));
        console.log("Account: ", address(account));
        console.log("ModifyLiquidityRouter: ", address(modifyLiquidityRouter));
        console.log("Manager: ", address(manager));
        console.log("Bundler: ", bundler);
                console.log("Bundler Private Key: ", bundlerPrivateKey);
        console.log("Depositor: ", depositor);
        console.log("Depositor Private Key: ", depositorPrivateKey);
        console.log("LP1: ", lp1);
        console.log("LP1 Private Key: ", lp1PrivateKey);
        console.log("LP2: ", lp2);
        console.log("LP2 Private Key: ", lp2PrivateKey);
        console.log("EOA (Foundry default): ", EOA);
        console.log("EOA Private Key (hex): 0x%x", EOAPrivateKey);
        console.log("Receiver: ", receiver);

        // give token to lps
        token.mint(lp1, 1e17);

        // give token to EOA
        token.mint(EOA, 1000e18);

        vm.stopBroadcast();

        // fund participants from EOA
        vm.startBroadcast(EOA);
        address(bundler).call{value: 1e17 + 1e12}("");
        address(lp1).call{value: 1e17 + 1e12}("");

        vm.stopBroadcast();
    }

    /**
     * @dev Deploys a contract and returns its address
     * @param contractName Name of the contract
     * @return deployedAddress Address of the deployed contract
     */
    function deployCode(string memory contractName)
        internal
        override
        returns (address deployedAddress)
    {
        bytes memory bytecode = vm.getCode(contractName);
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployedAddress != address(0), "Deployment failed");
    }
}
