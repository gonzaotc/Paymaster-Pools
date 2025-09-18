// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/utils/CurrencySettler.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {Permit2} from "permit2/Permit2.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
// Internal
import {MinimalPaymasterCore} from "src/core/MinimalPaymasterCore.sol";

// Test
import {console} from "forge-std/console.sol";

/**
 * @title PaymasterPool
 * @author Gonzalo Othacehe
 * @notice A permissionless paymaster pool that allows users to access the Ethereum Protocol without
 *  ether, while enabling liquidity providers to earn a corresponding share of the fees.
 *
 * Conceptually: as the Uniswap protocol is an AMM that allows anyone to exchange tokens and LPs to
 *  provide the service while getting paid, think of PaymasterPools as an Automated Paymaster that allows
 *  users to get their user operations sponsored, and LPs to provide the service while getting paid.
 */
contract UniswapPaymaster is MinimalPaymasterCore {
    using ERC4337Utils for PackedUserOperation;
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for *;

    IPoolManager public immutable manager;
    Permit2 public immutable permit2;

    constructor(IPoolManager _manager, Permit2 _permit2) {
        manager = _manager;
        permit2 = _permit2;
    }

    // Revert if the caller is not the pool manager.
    error OnlyPoolManager();

    // Modifier to ensure the caller is the pool manager.
    modifier onlyPoolManager() {
        if (msg.sender != address(manager)) {
            revert OnlyPoolManager();
        }
        _;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    /// @dev User pre-pays for the user operation.
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, /* userOpHash */
        uint256 maxCost // measured in Wei
        // maxCost = (verificationGasLimit + callGasLimit + paymasterVerificationGasLimit
        //           + paymasterPostOpGasLimit + preVerificationGas) * maxFeePerGas
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        console.log("_validatePaymasterUserOp");
        console.log("Paymaster eth balance", address(this).balance);
        console.log("Entrypoint eth deposit", entryPoint().balanceOf(address(this)));

        // Decode the paymaster data to obtain PoolKey and AllowanceTransfer permit
        (
            PoolKey memory poolKey,
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = abi.decode(userOp.paymasterData(), (PoolKey, IAllowanceTransfer.PermitSingle, bytes));

        if (
            !poolKey.currency0.isAddressZero() // the pool is not [ETH, token]
                || permitSingle.details.token != Currency.unwrap(poolKey.currency1) // the token mismatch
                || permitSingle.spender != address(this) // the spender is not this paymaster
                || permitSingle.sigDeadline < block.timestamp // the signature is expired
                || permitSingle.details.expiration < block.timestamp // the permit is expired
        ) {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }

        // Establish the allowance using the signed permit
        // This gives our paymaster permission to transfer tokens from the user later
        try permit2.permit(userOp.sender, permitSingle, signature) {}
        catch {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }

        // Calculate the required ether prefund
        console.log("_validatePaymasterUserOp - maxCost", maxCost);

        try manager.unlock(
            abi.encode(
                CallbackData(
                    userOp.sender, // Use userOp.sender, not msg.sender (which is EntryPoint)
                    poolKey,
                    SwapParams({
                        zeroForOne: false, // token -> ether
                        amountSpecified: int256(maxCost), // specific output
                        sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1 // disable slippage protection for now
                    })
                )
            )
        ) {
            return (
                // Encode the validation context required for the postOp
                abi.encode(userOp.sender, maxCost),
                ERC4337Utils.SIG_VALIDATION_SUCCESS
            );
        } catch {
            // If the swap fails, return validation failed.
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }
    }

    // Called back by the pool manager after the swap is init.
    function unlockCallback(bytes calldata rawData)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta swapDelta = manager.swap(data.key, data.params, "");
        console.log("swapDelta amount0", swapDelta.amount0().toUint256());
        console.log("swapDelta amount1", (-(swapDelta.amount1())).toUint256());

        // Calculate exact amount of tokens needed for the swap
        uint256 tokenAmountIn = (-(swapDelta.amount1())).toUint256();

        console.log("taking tokens from user", tokenAmountIn);
        // Transfer the exact tokens needed from user using our established allowance
        // This is the magic! User signed a permit for large amount, we transfer exact amount needed
        permit2.transferFrom(
            data.sender, // from: user who signed the permit
            address(this), // to: this paymaster
            uint160(tokenAmountIn), // amount: exact amount needed (cast to uint160)
            Currency.unwrap(data.key.currency1) // token: the token address
        );

        console.log("settling tokens to the pool manager", tokenAmountIn);
        // Settle the tokens with pool manager
        data.key.currency1.settle(manager, address(this), tokenAmountIn, false);

        console.log("taking ether from the pool manager", swapDelta.amount0().toUint256());
        // Take the ether from the pool manager to this paymaster's balance
        data.key.currency0.take(manager, address(this), swapDelta.amount0().toUint256(), false);

        return abi.encode(swapDelta);
    }

    /// @dev Refunds the user with any excess ether
    function _postOp(
        PostOpMode, /* mode */
        bytes calldata context,
        uint256 actualGasCost, // measured in Wei
        uint256 /* actualUserOpFeePerGas */
    ) internal virtual override {
        console.log("PostOp");
        (address userOpSender, uint256 maxCost) = abi.decode(context, (address, uint256));

        console.log("Prefunded maxCost", maxCost);
        console.log("Actual Gas Cost", actualGasCost);

        console.log("Paymaster eth balance", address(this).balance);
        console.log("Entrypoint eth deposit", entryPoint().balanceOf(address(this)));

        uint256 excess = maxCost - actualGasCost;

        console.log("PostOp - excess ether", excess);

        // Send back any excess ether to the user
        if (excess > 0) {
            console.log("PostOp - sending excess ether to the user");
            // Send the excess ether to the user. Do not revert if the call fails.
            (bool success,) = payable(userOpSender).call{value: excess}("");

            if (success) {
                console.log("PostOp - Refund succeeded");
            } else {
                console.log("PostOp - Refund failed");
            }
        }

        // Replenish the EntryPoint deposit with the actual gas cost
        // This ensures the paymaster can pay for future operations
        entryPoint().depositTo{value: actualGasCost}(address(this));

        console.log("PostOp - Paymaster eth balance after deposit", address(this).balance);
        console.log(
            "PostOp - Entrypoint eth deposit after deposit", entryPoint().balanceOf(address(this))
        );

        console.log("PostOp - finished");
    }

    /**
     * @dev Allows the contract to receive ETH from the pool manager
     * @notice This is needed to receive the ETH from the pool manager.
     */
    receive() external payable {}
}
