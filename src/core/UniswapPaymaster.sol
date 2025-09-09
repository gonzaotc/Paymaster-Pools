// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC6909TokenSupply} from
    "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909TokenSupply.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/utils/CurrencySettler.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {
    IPoolManager,
    BalanceDelta,
    ModifyLiquidityParams,
    SwapParams
} from "v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";

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

    constructor(IPoolManager _manager) {
        manager = _manager;
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
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        // Decode the paymaster data in order to obtain the PoolKey and permit parameters.
        (PoolKey memory poolKey, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(userOp.paymasterData(), (PoolKey, uint256, uint256, uint8, bytes32, bytes32));

        // If the pool is not initialized, or is not [ETH, token], return validation failed.
        if (!poolKey.currency0.isAddressZero() || address(poolKey.hooks) == address(0)) {
            console.log("Pool not initialized or not [ETH, token]");
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }

        address token = Currency.unwrap(poolKey.currency1);

        // Attempt to consume the permit signature, which may have been already consumed.
        try IERC20Permit(token).permit(userOp.sender, address(this), value, deadline, v, r, s) {
            console.log("Permit succeeded");
        } catch {
            console.log("Permit failed");
            // since permit failed, verify allowance
            if (IERC20(token).allowance(userOp.sender, address(this)) < value) {
                console.log("Allowance too low");
                return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
            }
        }

        // Calculate the required ether prefund
        uint256 etherPrefund = _ethCost(maxCost, userOp.maxFeePerGas());

        try manager.unlock(
            abi.encode(
                CallbackData(
                    msg.sender,
                    poolKey,
                    SwapParams({
                        zeroForOne: false, // token -> ether
                        amountSpecified: int256(etherPrefund),
                        sqrtPriceLimitX96: type(uint160).max // disable slippage protection for now
                    })
                )
            )
        ) {
            console.log("Swap succeeded");
            return (
                // Encode the validation context required for the postOp
                abi.encodePacked(userOp.sender, etherPrefund),
                ERC4337Utils.SIG_VALIDATION_SUCCESS
            );
        } catch {
            console.log("Swap failed");
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }
    }

    /// @dev Refunds the user with any excess ether
    function _postOp(
        PostOpMode, /* mode */
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        (address userOpSender, uint256 prefundedEther) = abi.decode(context, (address, uint256));
        
        uint256 actualCostInETH = _ethCost(actualGasCost, actualUserOpFeePerGas);

        assert(prefundedEther >= actualCostInETH); // Should always be true

        // Send back any excess ether to the user
        if (prefundedEther > actualCostInETH) {
            // Send the excess ether to the user. Do not revert if the call fails.
            payable(userOpSender).call{value: prefundedEther - actualCostInETH}("");
        }
    }

    // Called back by the pool manager after the swap.
    function unlockCallback(bytes calldata rawData)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, "");

        (Currency eth, Currency token) = (data.key.currency0, data.key.currency1);

        // Take the ether from the pool manager
        int256 ethDelta = manager.currencyDelta(address(this), eth);
        assert(ethDelta > 0); // Should always be positive.
        eth.take(manager, data.sender, ethDelta.toUint256(), false);

        // Send the token to the pool manager
        int256 tokenDelta = manager.currencyDelta(address(this), token);
        assert(tokenDelta < 0); // Should always be negative.
        token.settle(manager, data.sender, (-tokenDelta).toUint256(), false);

        return abi.encode(delta);
    }

    /// @dev Calculates the cost of the user operation in ETH
    function _ethCost(uint256 cost, uint256 feePerGas) internal view virtual returns (uint256) {
        return cost + _postOpCost() * feePerGas;
    }

    /// @dev Over-estimates the cost of the post-operation logic.
    /// @return Gas units estimated for postOp execution
    function _postOpCost() internal view virtual returns (uint256) {
        return 30_000;
    }

    /// @dev Denominator used for interpreting the tokenPrice to avoid precision loss.
    /// @return Scaling factor for fixed-point token price calculations (1e18)
    function _tokenPriceDenominator() internal view virtual returns (uint256) {
        return 1e18;
    }

    /// @dev Get the token price in ETH.
    function _getTokenPrice() internal pure returns (uint256) {
        return 1e18;
    }
}
