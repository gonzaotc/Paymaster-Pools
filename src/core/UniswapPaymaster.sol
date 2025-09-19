// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/utils/CurrencySettler.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {Permit2} from "permit2/Permit2.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

// Internal
import {MinimalPaymasterCore} from "src/core/MinimalPaymasterCore.sol";
import {EntryPointVault} from "src/core/EntryPointVault.sol";

/**
 * @title UniswapPaymaster
 * @author Gonzalo Othacehe
 * @notice A permissionless paymaster that allows anyone to pay for their transactions in any token.
 *
 * Complement to the Uniswap Protocol, converting any [ETH, Token] pool into a Paymaster Pool that
 * can be leveraged to pay transactions in any token. Liquidity providers from those pools enjoy
 * increased profits as a result of the increased capital utility, as the liquidity from those pools
 * serve for both users looking to swap, and users looking to pay for transactions in particular tokens.
 *
 * Can be used with ANY Uniswap V4 hooked or unhooked pool that supports native currency,
 */
contract UniswapPaymaster is MinimalPaymasterCore, EntryPointVault {
    using ERC4337Utils for PackedUserOperation;
    using CurrencySettler for Currency;
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

    /// @dev Validates the paymaster's willingness to pay for the user operation by executing a token-to-ETH swap.
    /// @dev Establishes a Permit2 allowance and swaps user tokens for the required ETH amount.
    function _validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32, uint256 maxCost)
        internal
        virtual
        override
        returns (bytes memory context, uint256 validationData)
    {
        (
            PoolKey memory poolKey,
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = abi.decode(userOp.paymasterData(), (PoolKey, IAllowanceTransfer.PermitSingle, bytes));

        if (
            !poolKey.currency0.isAddressZero() // the pool must support native currency
                || permitSingle.details.token != Currency.unwrap(poolKey.currency1) // permit token mismatch
                || permitSingle.spender != address(this) // permit spender mismatch
                || permitSingle.sigDeadline < block.timestamp // expired signature
                || permitSingle.details.expiration < block.timestamp // expired permit
        ) {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }

        // Consume the permit to increase the paymaster allowance
        try permit2.permit(userOp.sender, permitSingle, signature) {}
        catch {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }

        // Calculate the required ether prefund + postOp gas buffer
        uint256 prefundRequired = _ethCost(maxCost, userOp.maxFeePerGas());

        try manager.unlock(
            abi.encode(
                CallbackData(
                    userOp.sender,
                    poolKey,
                    SwapParams({
                        zeroForOne: false, // token -> ether
                        amountSpecified: int256(prefundRequired), // exact output
                        sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
                    })
                )
            )
        ) {
            return (abi.encode(userOp.sender, prefundRequired), ERC4337Utils.SIG_VALIDATION_SUCCESS);
        } catch {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }
    }

    /// @dev Called back by the pool manager after the swap is init.
    function unlockCallback(bytes calldata rawData)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta swapDelta = manager.swap(data.key, data.params, "");

        uint256 tokenAmountIn = (-(swapDelta.amount1())).toUint256();
        uint256 etherAmountOut = swapDelta.amount0().toUint256();

        // Transfer the exact tokens needed from user using our established allowance
        permit2.transferFrom(
            data.sender, // from: user who signed the permit
            address(this), // to: this paymaster
            uint160(tokenAmountIn), // amount: casted exact amount needed
            Currency.unwrap(data.key.currency1) // token: the token address
        );

        // Settle the tokens from this paymaster to the pool manager
        data.key.currency1.settle(manager, address(this), tokenAmountIn, false);

        // Take the ether from the pool manager to this paymaster's balance
        data.key.currency0.take(manager, address(this), etherAmountOut, false);

        return abi.encode(swapDelta);
    }

    /// @dev Refunds the user with any excess ether and refills the EntryPoint deposit.
    /// @dev Only refunds users if their operation succeeded to prevent economic attacks.
    /// @param mode Whether the user operation succeeded or reverted
    /// @param context Encoded user address and prefund amount from validation
    /// @param actualGasCost The actual gas cost consumed by the user operation
    /// @param actualUserOpFeePerGas The actual fee per gas paid
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        (address userOpSender, uint256 prefundRequired) = abi.decode(context, (address, uint256));

        uint256 totalUsed = _ethCost(actualGasCost, actualUserOpFeePerGas);

        uint256 excess = prefundRequired - totalUsed;

        // Only refund user if the operation succeeded
        if (excess > 0 && mode == PostOpMode.opSucceeded) {
            // forge-lint: disable-next-line
            payable(userOpSender).call{value: excess}("");
        }

        // Always refill the EntryPoint deposit with the actual gas cost
        entryPoint().depositTo{value: totalUsed}(address(this));
    }

    /// @dev Calculates the cost of the user operation in ETH.
    function _ethCost(uint256 cost, uint256 feePerGas) internal view virtual returns (uint256) {
        return (cost + _postOpCost() * feePerGas);
    }

    /// @dev Over-estimates the cost of the post-operation logic
    function _postOpCost() internal pure returns (uint256) {
        return 30_000;
    }

    function entryPoint()
        public
        view
        virtual
        override(MinimalPaymasterCore, EntryPointVault)
        returns (IEntryPoint)
    {
        return super.entryPoint();
    }

    /// @dev Allows the contract to temporarily receive ETH from the pool manager
    receive() external payable {}
}
