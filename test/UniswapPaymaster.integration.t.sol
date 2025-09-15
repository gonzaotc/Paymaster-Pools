// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
// import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
// import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
// import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// import {Deployers} from "v4-core/test/utils/Deployers.sol";
// import {Currency} from "v4-core/src/types/Currency.sol";
// import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";

// import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
// import {SimpleAccount} from "test/mocks/SimpleAccount.sol";
// import {UserOpHelper} from "test/helpers/UserOpHelper.sol";
// import {TestUtils} from "test/TestUtils.sol";
// import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";

// contract UniswapPaymasterIntegrationTest is Test, TestUtils, Deployers, UserOpHelper {
//     using StateLibrary for IPoolManager;
//     using ERC4337Utils for PackedUserOperation;

//     EntryPoint public entryPoint;
//     ERC20PermitMock public token;
//     UniswapPaymaster public paymaster;
//     SimpleAccount public account;

//     address public accountOwner;
//     uint256 public accountOwnerPrivateKey;
//     address public liquidityProvider;

//     function setUp() public {
//         // Deploy EntryPoint at canonical address
//         deployCodeTo(
//             "account-abstraction/contracts/core/EntryPoint.sol",
//             address(ERC4337Utils.ENTRYPOINT_V08)
//         );
//         entryPoint = EntryPoint(payable(address(ERC4337Utils.ENTRYPOINT_V08)));

//         // Deploy Uniswap infrastructure
//         deployFreshManagerAndRouters();

//         // Deploy paymaster
//         paymaster = new UniswapPaymaster(manager);

//         // Create test token
//         token = new ERC20PermitMock();

//         // Initialize pool: ETH/Token
//         (key,) = initPool(
//             Currency.wrap(address(0)), // ETH
//             Currency.wrap(address(token)), // Token
//             IHooks(address(0)), // No hooks
//             3000, // 0.3% fee
//             60, // tick spacing
//             SQRT_PRICE_1_1 // 1:1 price
//         );

//         // Create accounts
//         (accountOwner, accountOwnerPrivateKey) = makeAddrAndKey("accountOwner");
//         liquidityProvider = makeAddr("liquidityProvider");

//         // Deploy account contract
//         account = new SimpleAccount(accountOwner);

//         // Setup liquidity
//         _setupLiquidity();

//         // Fund paymaster with ETH for gas payments
//         vm.deal(address(paymaster), 10 ether);
//     }

//     function _setupLiquidity() internal {
//         // Give LP tokens and ETH
//         token.mint(liquidityProvider, 1000e18);
//         vm.deal(liquidityProvider, 100 ether);

//         vm.startPrank(liquidityProvider);

//         // Approve tokens
//         token.approve(address(manager), type(uint256).max);

//         // Add liquidity to the pool
//         modifyLiquidityRouter.modifyLiquidity(
//             key,
//             IPoolManager.ModifyLiquidityParams({
//                 tickLower: -60,
//                 tickUpper: 60,
//                 liquidityDelta: 1000e18,
//                 salt: bytes32(0)
//             }),
//             ""
//         );

//         vm.stopPrank();
//     }

//     function test_fullUserOperationFlow() public {
//         // 1. Setup: Give account owner tokens
//         token.mint(accountOwner, 100e18);

//         // 2. Account owner approves tokens to account contract
//         vm.prank(accountOwner);
//         token.approve(address(account), 100e18);

//         // 3. Fund account with tokens (simulate account receiving tokens)
//         vm.prank(accountOwner);
//         token.transfer(address(account), 50e18);

//         // 4. Create permit signature for paymaster
//         uint256 permitValue = 10e18;
//         uint256 deadline = block.timestamp + 1 hours;

//         (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
//             IERC20Permit(address(token)),
//             address(account),
//             address(paymaster),
//             permitValue,
//             deadline,
//             accountOwnerPrivateKey // Account owner signs permit
//         );

//         // 5. Build paymaster data
//         bytes memory paymasterData = abi.encode(
//             key, // PoolKey
//             permitValue, // permit value
//             deadline, // permit deadline
//             v, r, s // permit signature
//         );

//         bytes memory fullPaymasterData = abi.encodePacked(
//             address(paymaster), // paymaster address
//             uint128(300_000), // verification gas limit
//             uint128(100_000), // post-op gas limit
//             paymasterData // paymaster-specific data
//         );

//         // 6. Build UserOperation
//         bytes memory callData = abi.encodeWithSelector(
//             SimpleAccount.execute.selector,
//             address(token),
//             0,
//             abi.encodeWithSelector(token.transfer.selector, accountOwner, 1e18)
//         );

//         PackedUserOperation memory userOp = buildUserOp(
//             address(account),
//             account.getNonce(),
//             callData,
//             fullPaymasterData
//         );

//         // 7. Sign UserOperation
//         userOp = signUserOp(userOp, accountOwnerPrivateKey, address(entryPoint));

//         // 8. Execute UserOperation through EntryPoint
//         PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
//         userOps[0] = userOp;

//         // Fund account with ETH for potential gas payments
//         vm.deal(address(account), 1 ether);

//         // Execute the user operation
//         vm.expectEmit(true, true, true, true);
//         // We expect the transfer to succeed
//         emit Transfer(address(account), accountOwner, 1e18);

//         entryPoint.handleOps(userOps, payable(liquidityProvider));

//         // 9. Verify results
//         // Account should have less tokens (1e18 transferred out)
//         assertEq(token.balanceOf(address(account)), 49e18);
//         // Account owner should have received the tokens
//         assertEq(token.balanceOf(accountOwner), 51e18); // 100 - 50 + 1
//     }

//     function test_paymasterValidation_invalidPool() public {
//         // Create invalid pool key (token as currency0 instead of ETH)
//         PoolKey memory invalidKey = PoolKey({
//             currency0: Currency.wrap(address(token)), // Invalid: should be ETH
//             currency1: Currency.wrap(address(0)),
//             fee: 3000,
//             tickSpacing: 60,
//             hooks: IHooks(address(0))
//         });

//         bytes memory paymasterData = abi.encode(
//             invalidKey,
//             10e18, // value
//             block.timestamp + 1 hours, // deadline
//             uint8(27), bytes32(0), bytes32(0) // dummy signature
//         );

//         bytes memory fullPaymasterData = abi.encodePacked(
//             address(paymaster),
//             uint128(300_000),
//             uint128(100_000),
//             paymasterData
//         );

//         PackedUserOperation memory userOp = buildUserOp(
//             address(account),
//             0,
//             "",
//             fullPaymasterData
//         );

//         // This should fail validation
//         vm.prank(address(entryPoint));
//         (bytes memory context, uint256 validationData) = paymaster.validatePaymasterUserOp(
//             userOp,
//             bytes32(0),
//             1e18
//         );

//         assertEq(context.length, 0);
//         assertEq(validationData, ERC4337Utils.SIG_VALIDATION_FAILED);
//     }

//     function test_paymasterValidation_insufficientAllowance() public {
//         // Create valid pool key but insufficient allowance
//         bytes memory paymasterData = abi.encode(
//             key,
//             100e18, // Large value that exceeds allowance
//             block.timestamp + 1 hours,
//             uint8(27), bytes32(0), bytes32(0) // Invalid signature (will fail permit)
//         );

//         bytes memory fullPaymasterData = abi.encodePacked(
//             address(paymaster),
//             uint128(300_000),
//             uint128(100_000),
//             paymasterData
//         );

//         PackedUserOperation memory userOp = buildUserOp(
//             address(account),
//             0,
//             "",
//             fullPaymasterData
//         );

//         // This should fail due to insufficient allowance
//         vm.prank(address(entryPoint));
//         (bytes memory context, uint256 validationData) = paymaster.validatePaymasterUserOp(
//             userOp,
//             bytes32(0),
//             1e18
//         );

//         assertEq(context.length, 0);
//         assertEq(validationData, ERC4337Utils.SIG_VALIDATION_FAILED);
//     }

//     // Helper to emit Transfer event for testing
//     event Transfer(address indexed from, address indexed to, uint256 value);
// }
