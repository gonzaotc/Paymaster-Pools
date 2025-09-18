// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/interfaces/IPoolManager.sol";

import {Permit2} from "permit2/Permit2.sol";

// Internal
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";
import {MinimalAccountEIP7702} from "test/mocks/accounts/MinimalAccountEIP7702.sol";
import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
import {UserOpHelper} from "test/helpers/UserOpHelper.sol";
import {TestingUtils} from "test/helpers/TestingUtils.sol";

// Test
import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract PaymasterTest is Test, Deployers, UserOpHelper, TestingUtils {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using ERC4337Utils for *;
    using TickMath for *;
    using SafeCast for *;

    // The ERC-4337 EntryPoint Singleton
    EntryPoint public entryPoint;
    // The ERC-4337 bundler
    address public bundler;
    // Someone funding the Paymaster in the EntryPointwith an initial deposit
    address public depositor;

    // The Permit2 Singleton
    Permit2 public permit2;

    // The UniswapPaymaster contract being tested
    UniswapPaymaster public paymaster;

    // An ERC-20 token accepted by a particular [ETH, token] pool
    ERC20PermitMock public token;
    // People providing liquidity to the pool
    address lp1;
    // People providing liquidity to the pool
    address lp2;

    // The EOA that will get sponsored by the paymaster
    // forge-lint: disable-next-line
    address EOA;
    // The private key of the EOA used to sign the user operations
    // forge-lint: disable-next-line
    uint256 EOAPrivateKey;

    // An OpenZeppelin ERC-4337 ECDSA Account Instance to delegate to
    MinimalAccountEIP7702 public account;

    // Someone receiving tokens from "EOA" because of the sponsored userop
    address receiver;

    struct GasConfiguration {
        uint256 callGasLimit; // The amount of gas to allocate the main execution call
        uint256 verificationGasLimit; //The amount of gas to allocate for the verification step
        uint256 preVerificationGas; // Extra gas to pay the bundler
        uint256 paymasterVerificationGasLimit; // The amount of gas to allocate for the paymaster validation code (only if paymaster exists)
        uint256 paymasterPostOpGasLimit; // The amount of gas to allocate for the paymaster post-operation code (only if paymaster exists)
        uint256 maxFeePerGas; // Maximum fee per gas (similar to EIP-1559 max_fee_per_gas)
        uint256 maxPriorityFeePerGas; // Maximum priority fee per gas (similar to EIP-1559 max_priority_fee_per_gas)
    }

    function setUp() public {
        // deploy the entrypoint
        deployCodeTo(
            "account-abstraction/contracts/core/EntryPoint.sol",
            address(ERC4337Utils.ENTRYPOINT_V08)
        );
        entryPoint = EntryPoint(payable(address(ERC4337Utils.ENTRYPOINT_V08)));

        // deploy uniswap interface
        deployFreshManagerAndRouters();

        // deploy Permit2
        permit2 = new Permit2();

        // deploy the paymaster
        paymaster = new UniswapPaymaster(manager, permit2);

        // create a ERC20 with permit.
        token = new ERC20PermitMock();

        // Deploy the ECDSA account to delegate to
        account = new MinimalAccountEIP7702();

        // initialize the pool
        (key,) = initPool(
            Currency.wrap(address(0)), // native currency
            Currency.wrap(address(token)), // token currency
            IHooks(address(0)), // hooks
            1000, // fee
            60, // tick spacing
            SQRT_PRICE_1_1 // sqrt price x96
        );

        // create accounts
        (bundler) = makeAddr("bundler");
        (depositor) = makeAddr("depositor");
        (lp1) = makeAddr("lp1");
        (lp2) = makeAddr("lp2");
        (EOA, EOAPrivateKey) = makeAddrAndKey("EOA");
        (receiver) = makeAddr("receiver");

        // fund bundler
        vm.deal(bundler, 1e18);

        // fund depositor
        vm.deal(depositor, 1e18);
        // depositor funds the paymaster
        vm.prank(depositor);
        entryPoint.depositTo{value: 1e18}(address(paymaster));

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

    function _getTickLower() public pure returns (int24) {
        return -60;
    }

    function _getTickUpper() public pure returns (int24) {
        return 60;
    }

    function _liquidityParams(int256 liquidityDelta)
        public
        pure
        returns (ModifyLiquidityParams memory)
    {
        return ModifyLiquidityParams({
            tickLower: _getTickLower(),
            tickUpper: _getTickUpper(),
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });
    }

    function test_permit2_allowance_EOA() public {
        // 1. Setup: Give user tokens and approve Permit2
        token.mint(EOA, 1000e18);
        vm.prank(EOA);
        token.approve(address(permit2), type(uint256).max);

        // 2. User signs AllowanceTransfer permit (off-chain, gasless)
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: type(uint160).max, // Large allowance
                expiration: uint48(block.timestamp + 1 hours), // 1 hour
                nonce: 0
            }),
            spender: address(paymaster), // Paymaster gets permission
            sigDeadline: uint48(block.timestamp + 1 hours) // 1 hour
        });
        bytes memory signature = _signPermit2Allowance(permit2, EOAPrivateKey, permitSingle);

        // 3. Establish the allowance (would happen in paymaster validation)
        permit2.permit(EOA, permitSingle, signature);

        // 4. Verify allowance was established
        (uint160 amount, uint48 exp, uint48 storedNonce) =
            permit2.allowance(EOA, address(token), address(paymaster));
        assertEq(amount, permitSingle.details.amount);
        assertEq(exp, permitSingle.details.expiration);
        assertEq(storedNonce, permitSingle.details.nonce + 1); // Nonce is incremented

        // 5. Paymaster can now transfer exact amounts as needed
        uint256 exactAmount = 100e18;
        uint256 balanceBefore = token.balanceOf(address(paymaster));
        vm.prank(address(paymaster));
        permit2.transferFrom(EOA, address(paymaster), uint160(exactAmount), address(token));
        uint256 balanceAfter = token.balanceOf(address(paymaster));
        assertEq(balanceAfter - balanceBefore, exactAmount);
    }

    function test_eip7702_delegation() public {
        assertEq(address(EOA).code.length, 0);

        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);

        vm.attachDelegation(signedDelegation);

        bytes memory expectedCode = abi.encodePacked(hex"ef0100", address(account));
        assertEq(address(EOA).code, expectedCode);
    }

    function test_ERC1271_signature() public {
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);
        vm.attachDelegation(signedDelegation);

        string memory text = "Hello, world!";
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n13", text));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOAPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = IERC1271(EOA).isValidSignature(hash, signature);
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function test_permit2_allowance_EIP7702() public {
        // 1. Setup: Give user tokens and approve Permit2
        token.mint(EOA, 1000e18);
        vm.prank(EOA);
        token.approve(address(permit2), type(uint256).max);

        // 2. Delegate to the account
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);
        vm.attachDelegation(signedDelegation);

        // 3. User signs AllowanceTransfer permit (off-chain, gasless)
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: type(uint160).max, // Large allowance
                expiration: uint48(block.timestamp + 1 hours), // 1 hour
                nonce: 0
            }),
            spender: address(paymaster), // Paymaster gets permission
            sigDeadline: uint48(block.timestamp + 1 hours) // 1 hour
        });
        bytes memory signature = _signPermit2Allowance(permit2, EOAPrivateKey, permitSingle);

        // 3. Establish the allowance (would happen in paymaster validation)
        permit2.permit(EOA, permitSingle, signature);

        // 4. Verify allowance was established
        (uint160 amount, uint48 exp, uint48 storedNonce) =
            permit2.allowance(EOA, address(token), address(paymaster));
        assertEq(amount, permitSingle.details.amount);
        assertEq(exp, permitSingle.details.expiration);
        assertEq(storedNonce, permitSingle.details.nonce + 1); // Nonce is incremented

        // 5. Paymaster can now transfer exact amounts as needed
        uint256 exactAmount = 100e18;
        uint256 balanceBefore = token.balanceOf(address(paymaster));
        vm.prank(address(paymaster));
        permit2.transferFrom(EOA, address(paymaster), uint160(exactAmount), address(token));
        uint256 balanceAfter = token.balanceOf(address(paymaster));
        assertEq(balanceAfter - balanceBefore, exactAmount);
    }

    function test_sponsor_user_operation() public {
        assertEq(address(paymaster).balance, 0);
        assertEq(entryPoint.balanceOf(address(paymaster)), 1e18);

        // 0. Frist requirement: EOA must approve Permit2
        // @tbd we MAY support both Permit1 and Permit2 to remove this step on ERC-2616 tokens.
        vm.prank(EOA);
        token.approve(address(permit2), type(uint256).max);

        // 1. EOA has 1000 tokens but no eth.
        token.mint(EOA, 1000e18);

        // 2. Delegate to the account
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);
        vm.attachDelegation(signedDelegation);

        // 2. Create gasless permit2 signature for paymaster
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: type(uint160).max, // Large allowance
                expiration: uint48(block.timestamp + 1 hours), // 1 hour
                nonce: 0
            }),
            spender: address(paymaster), // Paymaster gets permission
            sigDeadline: uint48(block.timestamp + 1 hours) // 1 hour
        });
        bytes memory signature = _signPermit2Allowance(permit2, EOAPrivateKey, permitSingle);

        GasConfiguration memory gasConfig = GasConfiguration({
            preVerificationGas: 50_000, // Extra gas to pay the bundler operational costs such as bundle tx cost and entrypoint static code execution.
            verificationGasLimit: 75_000, // The amount of gas to allocate for the verification step
            paymasterVerificationGasLimit: 300_000, // The amount of gas to allocate for the paymaster validation code (only if paymaster exists)
            paymasterPostOpGasLimit: 50_000, // The amount of gas to allocate for the paymaster post-operation code (only if paymaster exists)
            callGasLimit: 50_000, // The amount of gas to allocate the main execution call
            maxPriorityFeePerGas: 1 gwei, // Maximum priority fee per gas (similar to EIP-1559 max_priority_fee_per_gas)
            maxFeePerGas: 1 gwei // Maximum fee per gas (similar to EIP-1559 max_fee_per_gas)
        });

        // 3. Build paymaster data
        bytes memory paymasterData = buildPaymasterData(
            address(paymaster), // paymaster
            uint128(gasConfig.paymasterVerificationGasLimit), // verification gas limit
            uint128(gasConfig.paymasterPostOpGasLimit), // post-op gas limit
            key, // pool key
            permitSingle, // permit single
            signature // signature
        );

        // 4. Build calldata
        bytes memory callData = abi.encodeWithSelector(
            MinimalAccountEIP7702.execute.selector,
            address(token),
            0,
            abi.encodeWithSelector(token.transfer.selector, receiver, 1e18)
        );

        // 5. Build UserOperation
        PackedUserOperation memory userOp = buildUserOp(
            EOA,
            MinimalAccountEIP7702(payable(EOA)).getNonce(),
            callData,
            paymasterData,
            gasConfig.verificationGasLimit,
            gasConfig.callGasLimit,
            gasConfig.preVerificationGas,
            gasConfig.maxPriorityFeePerGas,
            gasConfig.maxFeePerGas
        );

        // 6. Sign UserOperation
        userOp = this.signUserOp(userOp, EOAPrivateKey, address(entryPoint));

        // 7. Execute the user operation
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        uint256 bundlerBalanceBefore = bundler.balance;
        uint256 entrypointDepositBefore = entryPoint.balanceOf(address(paymaster));

        console.log("Sponsoring!");
        vm.startPrank(bundler);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(EOA, receiver, 1e18);
        IEntryPoint(address(entryPoint)).handleOps(userOps, payable(bundler));
        vm.stopPrank();
        console.log("Sponsoring done!");

        uint256 paymasterBalanceAfter = address(paymaster).balance;
        uint256 bundlerBalanceAfter = bundler.balance;
        uint256 entrypointDepositAfter = entryPoint.balanceOf(address(paymaster));

        int256 bundlerDelta = int256(bundlerBalanceAfter) - int256(bundlerBalanceBefore);
        int256 entrypointDelta = int256(entrypointDepositAfter) - int256(entrypointDepositBefore);

        console.log("paymaster balance after", paymasterBalanceAfter);
        console.log("bundler delta", bundlerDelta);
        console.log("entrypoint delta", entrypointDelta);

        // 9. Verify results
        // Receiver should have received the tokens
        assertEq(token.balanceOf(receiver), 1e18);

        // Paymaster should not have any eth.
        assertEq(paymasterBalanceAfter, 0);

        // Bundler should have made a profit.
        assertGt(bundlerBalanceAfter, bundlerBalanceBefore);

        // Paymaster deposit should NOT have been decreased.
        assertGe(entrypointDepositAfter, entrypointDepositBefore);
    }
}
