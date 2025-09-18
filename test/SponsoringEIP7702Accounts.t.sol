// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// // External
// import {Test, Vm} from "forge-std/Test.sol";
// import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
// import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
// import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
// import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
// import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import {Deployers} from "v4-core/test/utils/Deployers.sol";
// import {Currency} from "v4-core/src/types/Currency.sol";
// import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {TickMath} from "v4-core/src/libraries/TickMath.sol";
// import {Permit2} from "permit2/Permit2.sol";

// // Internal
// import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";
// import {MinimalAccountEIP7702} from "test/mocks/accounts/MinimalAccountEIP7702.sol";
// import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
// import {UserOpHelper} from "test/helpers/UserOpHelper.sol";
// import {TestingUtils} from "test/helpers/TestingUtils.sol";

// // Test
// import {console} from "forge-std/console.sol";

// contract PaymasterTest is Test, Deployers, UserOpHelper, TestingUtils {
//     using PoolIdLibrary for PoolKey;
//     using StateLibrary for IPoolManager;
//     using ERC4337Utils for *;
//     using TickMath for *;
//     using SafeCast for *;

//     // The ERC-4337 EntryPoint Singleton
//     EntryPoint public entryPoint;
//     // The ERC-4337 bundler
//     address public bundler;
//     // Someone funding the Paymaster in the EntryPointwith an initial deposit
//     address public depositor;

//     // The Permit2 Singleton
//     Permit2 public permit2;

//     // The UniswapPaymaster contract being tested
//     UniswapPaymaster public paymaster;

//     // An ERC-20 token accepted by a particular [ETH, token] pool
//     ERC20Mock public token;
//     // People providing liquidity to the pool
//     address lp1;
//     // People providing liquidity to the pool
//     address lp2;

//     // The EOA that will get sponsored by the paymaster
//     address EOA;
//     // The private key of the EOA used to sign the user operations
//     uint256 EOAPrivateKey;

//     // An OpenZeppelin ERC-4337 Minimal Account instance to delagate to
//     MinimalAccountEIP7702 public account;

//     // Someone receiving tokens from "EOA" because of the sponsored userop
//     address receiver;

//     struct GasConfiguration {
//         uint256 callGasLimit; // The amount of gas to allocate the main execution call
//         uint256 verificationGasLimit; //The amount of gas to allocate for the verification step
//         uint256 preVerificationGas; // Extra gas to pay the bundler
//         uint256 paymasterVerificationGasLimit; // The amount of gas to allocate for the paymaster validation code (only if paymaster exists)
//         uint256 paymasterPostOpGasLimit; // The amount of gas to allocate for the paymaster post-operation code (only if paymaster exists)
//         uint256 maxFeePerGas; // Maximum fee per gas (similar to EIP-1559 max_fee_per_gas)
//         uint256 maxPriorityFeePerGas; // Maximum priority fee per gas (similar to EIP-1559 max_priority_fee_per_gas)
//     }

//     function setUp() public {
//         // deploy the entrypoint
//         deployCodeTo(
//             "account-abstraction/contracts/core/EntryPoint.sol",
//             address(ERC4337Utils.ENTRYPOINT_V08)
//         );
//         entryPoint = EntryPoint(payable(address(ERC4337Utils.ENTRYPOINT_V08)));

//         // deploy uniswap interface
//         deployFreshManagerAndRouters();

//         // deploy Permit2
//         permit2 = new Permit2();

//         // deploy the paymaster
//         paymaster = new UniswapPaymaster(manager, permit2);

//         // create a ERC20 with permit.
//         token = new ERC20Mock();

//         // An OpenZeppelin ERC-4337 EIP-7702 Account instance to delegate to
//         account = new MinimalAccountEIP7702();

//         // initialize the pool
//         (key,) = initPool(
//             Currency.wrap(address(0)), // native currency
//             Currency.wrap(address(token)), // token currency
//             IHooks(address(0)), // hooks
//             1000, // fee
//             60, // tick spacing
//             SQRT_PRICE_1_1 // sqrt price x96
//         );

//         // create accounts
//         (bundler) = makeAddr("bundler");
//         (depositor) = makeAddr("depositor");
//         (lp1) = makeAddr("lp1");
//         (lp2) = makeAddr("lp2");
//         (EOA, EOAPrivateKey) = makeAddrAndKey("EOA");
//         (receiver) = makeAddr("receiver");

//         // fund bundler
//         vm.deal(bundler, 1e18);
//     }

//     function test_eip7702_delegation() public {
//         assertEq(address(EOA).code.length, 0);

//         Vm.SignedDelegation memory signedDelegation =
//             vm.signDelegation(address(account), EOAPrivateKey);

//         vm.attachDelegation(signedDelegation);

//         bytes memory expectedCode = abi.encodePacked(hex"ef0100", address(account));
//         assertEq(address(EOA).code, expectedCode);
//     }

//     // function test_sponsor_user_operation() public {
//     //     // Add EIP-7702 cost => https://eips.ethereum.org/EIPS/eip-4337
//     //     // userOp.preVerificationGas += 25000; // PER_EMPTY_ACCOUNT_COST for EIP-7702
//     // }
// }
