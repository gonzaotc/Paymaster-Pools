// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {Test, Vm} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/interfaces/IPoolManager.sol";

// Internal
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";
import {SimpleEIP7702Account} from "test/mocks/SimpleEIP7702Account.sol";
import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
import {UserOpHelper} from "test/helpers/UserOpHelper.sol";
import {TestingUtils} from "test/helpers/TestingUtils.sol";

// Test
import {console} from "forge-std/console.sol";

contract PaymasterTest is Test, Deployers, UserOpHelper, TestingUtils {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using ERC4337Utils for *;
    using TickMath for *;
    using SafeCast for *;

    EntryPoint public entryPoint;
    ERC20PermitMock public token;
    UniswapPaymaster public paymaster;

    address public bundler;
    address public depositor;

    address lp1;
    address lp2;

    SimpleEIP7702Account public account;
    address EOA;
    uint256 EOAPrivateKey;

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

        // deploy the paymaster
        paymaster = new UniswapPaymaster(manager);

        // create a ERC20 with permit.
        token = new ERC20PermitMock();

        // Deploy account contract
        account = new SimpleEIP7702Account();

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

        // setup liquidity
        _setupLiquidity();
    }

    function _getTickLower() public view returns (int24) {
        // return TickMath.minUsableTick(key.tickSpacing);
        return -60;
    }

    function _getTickUpper() public view returns (int24) {
        // return TickMath.maxUsableTick(key.tickSpacing);
        return 60;
    }

    function _liquidityParams(int256 liquidityDelta)
        public
        view
        returns (ModifyLiquidityParams memory)
    {
        return ModifyLiquidityParams({
            tickLower: _getTickLower(),
            tickUpper: _getTickUpper(),
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });
    }

    function _setupLiquidity() internal {
        // give eth to lps
        vm.deal(lp1, 1e20);
        vm.deal(lp2, 1e20);

        // give token to lps
        token.mint(lp1, 1e20);
        token.mint(lp2, 1e20);

        // get eth amounts for 1e15 liquidity
        (uint256 ethAmount,) =
            getAmountsForLiquidity(manager, key, 1e18, _getTickLower(), _getTickUpper());
        uint256 ethAmountPlusBuffer = ethAmount * 110 / 100; // 10% buffer, rest is refunded

        // lp1 adds 1e18 liquidity
        vm.startPrank(lp1);
        token.approve(address(manager), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmountPlusBuffer}(
            key, _liquidityParams(1e18), ""
        );
        vm.stopPrank();

        // lp2 adds 1e18 liquidity
        vm.startPrank(lp2);
        token.approve(address(manager), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmountPlusBuffer}(
            key, _liquidityParams(1e18), ""
        );
        vm.stopPrank();
    }

    function test_swap_success() public {
        // deal tokens
        token.mint(address(this), 1e20);
        // approve the swap router
        token.approve(address(swapRouter), type(uint256).max);
        BalanceDelta delta = swap(
            key,
            false, // token -> ether,
            int256(1e15), // exact output (ether)
            ""
        );

        // verify the delta
        assertEq(delta.amount0(), 1e15);
        assertEq(delta.amount1(), -1001501751876940);
    }

    function test_permit_success() public {
        // Setup permit parameters
        uint256 value = type(uint256).max;
        uint256 deadline = type(uint256).max;

        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            IERC20Permit(address(token)), EOA, address(paymaster), value, deadline, EOAPrivateKey
        );

        // Call permit directly on the token
        token.permit(EOA, address(paymaster), value, deadline, v, r, s);

        // Verify that the allowance was set correctly
        assertEq(token.allowance(EOA, address(paymaster)), value);
    }

    function test_eip7702_delegation() public {
        assertEq(address(EOA).code.length, 0);

        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);

        // attach delegation
        vm.attachDelegation(signedDelegation);

        bytes memory expectedCode = abi.encodePacked(hex"ef0100", address(account));
        assertEq(address(EOA).code, expectedCode);
    }

    function test_sponsor_user_operation() public {
        // 1. EOA has 1000 tokens but no eth.
        token.mint(EOA, 1000e18);

        // 2. Create gasless permit signature for paymaster
        uint256 permitValue = type(uint256).max; // max for now
        uint256 permitDeadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            IERC20Permit(address(token)), // token
            EOA, // sender
            address(paymaster), // spender
            permitValue, // value,
            permitDeadline, // deadline
            EOAPrivateKey // owner private key
        );

        // 3. Create EIP-7702 delegation (EOA → SimpleEIP7702Account)
        Vm.SignedDelegation memory signedDelegation =
            vm.signDelegation(address(account), EOAPrivateKey);

        GasConfiguration memory gasConfig = GasConfiguration({
            verificationGasLimit: 300_000,
            callGasLimit: 100_000,
            preVerificationGas: 50_000,
            paymasterVerificationGasLimit: 100_000,
            paymasterPostOpGasLimit: 100_000,
            maxPriorityFeePerGas: 1 gwei,
            maxFeePerGas: 2 gwei
        });

        // 3. Build paymaster data
        bytes memory paymasterData = buildPaymasterData(
            address(paymaster), // paymaster
            uint128(gasConfig.paymasterVerificationGasLimit), // verification gas limit
            uint128(gasConfig.paymasterPostOpGasLimit), // post-op gas limit
            key, // pool key
            permitValue, // permit value
            permitDeadline, // permit deadline
            v, // permit signature (v)
            r, // permit signature (r)
            s // permit signature (s)
        );

        // 4. Build calldata
        bytes memory callData = abi.encodeWithSelector(
            SimpleEIP7702Account.execute.selector,
            address(token),
            0,
            abi.encodeWithSelector(token.transfer.selector, receiver, 1e18)
        );

        // 5. Build UserOperation
        PackedUserOperation memory userOp = buildUserOp(
            EOA,
            account.getNonce(),
            callData,
            paymasterData,
            gasConfig.verificationGasLimit,
            gasConfig.callGasLimit,
            gasConfig.preVerificationGas,
            gasConfig.maxPriorityFeePerGas,
            gasConfig.maxFeePerGas
        );
        console.log("User operation built!");

        // Add EIP-7702 cost
        userOp.preVerificationGas += 25000; // PER_EMPTY_ACCOUNT_COST for EIP-7702

        // 6. Sign UserOperation
        userOp = this.signUserOp(userOp, EOAPrivateKey, address(entryPoint));
        console.log("User operation signed!");

        // 7. Execute the user operation
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        /// just for now, deposit 1eth in the entrypoint
        vm.startPrank(depositor);
        vm.deal(address(depositor), 1e18);
        entryPoint.depositTo{value: 1e18}(address(paymaster));
        vm.stopPrank();

        console.log("Sponsoring!");
        vm.startPrank(bundler);
        vm.attachDelegation(signedDelegation);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(account), receiver, 1e18);
        IEntryPoint(address(entryPoint)).handleOps(userOps, payable(bundler));
        vm.stopPrank();
        console.log("Sponsoring done!");

        // 9. Verify results
        // Receiver should have received the tokens
        assertEq(token.balanceOf(receiver), 1e18);
        // Account should have less tokens (1e18 transferred out)
        assertEq(token.balanceOf(address(account)), 999e18);
    }
}
