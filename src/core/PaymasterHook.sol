// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";

// Internal
import {MinimalPaymasterCore} from "src/core/MinimalPaymasterCore.sol";

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
contract PaymasterHook is MinimalPaymasterCore, BaseHook, ERC6909TokenSupply {
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;
    using ERC4337Utils for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using ERC4337Utils for PackedUserOperation;

    /// @dev When initializing the hook, the currency0 must be native.
    error OnlyNativeCurrency();

    /// @dev Liquidity was attempted to be added or removed via the `PoolManager` instead of the hook.
    error LiquidityOnlyViaHook();

    /// @dev The amount of native currency sent is not the same as the amount of native currency expected.
    error InvalidNativeAmount();

    /// @dev Pool was not initialized.
    error PoolNotInitialized();

    /// @dev Parameters for adding liquidity.
    /// @param sender The address of liquidity provider.
    /// @param poolKey The key of the pool.
    /// @param amount0 The amount of native currency to deposit.
    /// @param amount1 The amount of token to deposit.
    struct AddLiquidityParams {
        address sender;
        PoolKey poolKey;
        uint256 amount0;
        uint256 amount1;
    }

    /// @dev Parameters for removing liquidity.
    /// @param sender The address of liquidity provider.
    /// @param poolKey The key of the pool.
    /// @param amount0 The amount of native currency to withdraw.
    /// @param amount1 The amount of token to withdraw.
    struct RemoveLiquidityParams {
        address sender;
        PoolKey poolKey;
        uint256 amount0;
        uint256 amount1;
    }

    /// @dev Check if the pool is initialized.
    modifier onlyInitializedPool(PoolKey calldata poolKey) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
        _;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /// @dev Initialize the pool.
    /// Note that currency0 must always be native, as only [ETH, token] pairs are supported.
    function _beforeInitialize(address, PoolKey calldata key, uint160)
        internal
        pure
        override
        returns (bytes4)
    {
        if (!key.currency0.isAddressZero()) revert OnlyNativeCurrency();
        return this.beforeInitialize.selector;
    }

    /// @dev Revert when liquidity is attempted to be added via the `PoolManager`.
    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        revert LiquidityOnlyViaHook();
    }

    /// @dev Revert when liquidity is attempted to be removed via the `PoolManager`.
    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        revert LiquidityOnlyViaHook();
    }

    /// @dev Add hook-owned liquidity.
    /// @param params The parameters for adding liquidity.
    /// Note that currency0 is always native, and currency1 is always the paymaster pool supported token.
    /// Note that ETH is kept deposited in the entry point, while the token is kept in the hook balance.
    // @TBD should take `liquidity` and convert it automatically to eth and
    // "You're minting shares based solely on ETH deposited, ignoring token"
    function addLiquidity(AddLiquidityParams calldata params)
        public
        payable
        virtual
        onlyInitializedPool(params.poolKey)
    {
        if (params.amount0 != msg.value) revert InvalidNativeAmount();

        // Deposit the native currency to the entry point
        entryPoint().depositTo{value: params.amount0}(address(this));

        // transfer currency1 (token) from the sender to the hook, allowance is required.
        IERC20(Currency.unwrap(params.poolKey.currency1)).safeTransferFrom(
            params.sender, address(this), params.amount1
        );

        // mint liquidity shares to the sender
        _mint(params.sender, poolKeyTokenId(params.poolKey), ethToShares(msg.value));
    }

    /// @dev Remove hook-owned liquidity.
    /// @param params The parameters for removing liquidity.
    function removeLiquidity(RemoveLiquidityParams calldata params) public payable virtual {
        // burn liquidity shares
        _burn(params.sender, poolKeyTokenId(params.poolKey), ethToShares(params.amount0));

        // withdraw the native currency from the entry point to the sender
        entryPoint().withdrawTo(payable(params.sender), params.amount0);

        // transfer currency1 (token) from the hook to the sender.
        IERC20(Currency.unwrap(params.poolKey.currency1)).safeTransfer(
            params.sender, params.amount1
        );
    }

    /// @dev Just-in-time liquidity provisioning
    /// Creates an unique hook-owned liquidity position with all the hook balances,
    /// providing both ETH and token for in-range liquidity.
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 1. Ether balance is in the entry point
        uint256 ethBalance = entryPoint().balanceOf(address(this));

        // 2. Token balance is already in the hook
        uint256 tokenBalance = key.currency1.balanceOfSelf();

        // 3. Calculate optimal liquidity for narrow range
        uint128 liquidity = _liquidityForAmounts(key, ethBalance, tokenBalance);

        // 5. Create the hook liquidity position
        _modifyLiquidity(key, liquidity.toInt256());

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @dev Remove the hook liquidity position and settle any pending deltas.
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        uint128 hookLiquidity = _getHookPositionLiquidity(key);

        // Remove the hook liquidity position
        if (hookLiquidity != 0) _modifyLiquidity(key, -hookLiquidity.toInt256());

        // Settle any pending deltas.
        _settlePendingDeltas(key);

        return (this.afterSwap.selector, 0);
    }

    /// Modify the hook-owned liquidity position.
    /// Requires the PoolManager to be unlocked due to the Flash Accounting model.
    function _modifyLiquidity(PoolKey calldata poolKey, int256 liquidityDelta)
        internal
        returns (BalanceDelta delta)
    {
        (delta,) = poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: getTickLower(poolKey),
                tickUpper: getTickUpper(poolKey),
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /// @dev Returns the lower tick boundary for the hook's liquidity position.
    function getTickLower(PoolKey calldata poolKey) public view virtual returns (int24) {
        return TickMath.minUsableTick(poolKey.tickSpacing);
    }

    /// @dev Returns the upper tick boundary for the hook's liquidity position.
    function getTickUpper(PoolKey calldata poolKey) public view virtual returns (int24) {
        return TickMath.maxUsableTick(poolKey.tickSpacing);
    }

    /// @dev Returns the current tick in a math reliable way.
    function getCurrentTick(PoolKey calldata poolKey) public view virtual returns (int24) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    /// @dev Convert ETH to shares, default to 1:1 ETH:shares.
    function ethToShares(uint256 eth) public pure returns (uint256) {
        return eth;
    }

    /// @dev Computes the maximum amount of liquidity received for a given amount of currency0 and currency1.
    /// may be inefficien since it may leave some liquidity unused, to be checked.
    function _liquidityForAmounts(PoolKey calldata poolKey, uint256 ethAmount, uint256 tokenAmount)
        internal
        view
        returns (uint128 liquidity)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(getTickLower(poolKey)),
            TickMath.getSqrtPriceAtTick(getTickUpper(poolKey)),
            ethAmount,
            tokenAmount
        );
    }

    /// @dev Get the liquidity of the hook's position.
    function _getHookPositionLiquidity(PoolKey calldata poolKey) internal view returns (uint128) {
        bytes32 positionKey = Position.calculatePositionKey(
            address(this), getTickLower(poolKey), getTickUpper(poolKey), bytes32(0)
        );
        return poolManager.getPositionLiquidity(poolKey.toId(), positionKey);
    }

    /// @dev Settle the pending deltas.
    ///
    /// Settle any pending delta resulting from
    ///    - beforeSwap liquidity provisioning
    ///    - swap
    ///    - afterSwap liquidity removal
    ///
    /// Ether will be taken or settled from the entry point.
    /// Token will be taken or settled from the hook.
    ///
    function _settlePendingDeltas(PoolKey calldata key) internal {
        int256 etherDelta = poolManager.currencyDelta(address(this), key.currency0);
        if (etherDelta > 0) {
            uint256 etherAmount = etherDelta.toUint256();
            key.currency0.take(poolManager, address(this), etherAmount, false);
            entryPoint().depositTo{value: etherAmount}(address(this));
        }
        if (etherDelta < 0) {
            uint256 etherAmount = (-etherDelta).toUint256();
            entryPoint().withdrawTo(payable(address(this)), etherAmount);
            key.currency0.settle(poolManager, address(this), etherAmount, false);
        }

        int256 tokenDelta = poolManager.currencyDelta(address(this), key.currency1);
        if (tokenDelta > 0) {
            uint256 tokenAmount = tokenDelta.toUint256();
            key.currency1.take(poolManager, address(this), tokenAmount, false);
        }
        if (tokenDelta < 0) {
            uint256 tokenAmount = (-tokenDelta).toUint256();
            key.currency1.settle(poolManager, address(this), tokenAmount, false);
        }
    }

    /// @dev Get the uint256 token ID for a pool key.
    function poolKeyTokenId(PoolKey calldata poolKey) public pure returns (uint256) {
        return uint256(PoolId.unwrap(poolKey.toId()));
    }

    /// @dev Validate the paymaster user operation.
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        // Decode the paymaster data in order to obtain the PoolKey and permit parameters.
        (PoolKey memory poolKey, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(userOp.paymasterData(), (PoolKey, uint256, uint256, uint8, bytes32, bytes32));

        address token = Currency.unwrap(poolKey.currency1);

        // Attempt to consume the permit signature, which may have been already consumed.
        // We continue even if it has been already consumed, because the current allowance may be enough.
        try IERC20Permit(token).permit(userOp.sender, address(this), value, deadline, v, r, s) {}
            catch {}

        // Get the token price in native currency from the pool
        uint256 tokenPriceInETH = _getTokenPriceFromPool(poolKey);

        // Convert the requiredPreFund to the token amount.
        uint256 tokenAmount = _erc20Cost(requiredPreFund, userOp.maxFeePerGas(), tokenPriceInETH);

        // Attempt to transfer the token from the user to the hook
        try IERC20(token).transferFrom(userOp.sender, address(this), tokenAmount) {
            return (
                // Encode the validation context required for the postOp
                abi.encodePacked(userOp.sender, token, tokenAmount, tokenPriceInETH),
                ERC4337Utils.SIG_VALIDATION_SUCCESS
            );
        } catch {
            return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
        }
    }

    /// @dev Post the paymaster user operation.
    function _postOp(
        PostOpMode, /* mode */
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        (address userOpSender, address token, uint256 prefundTokenAmount, uint256 prefundTokenPriceETH) =
            abi.decode(context, (address, address, uint256, uint256));

        // Calculate the actual token amount spent by the user operation.
        uint256 actualTokenAmount =
            _erc20Cost(actualGasCost, actualUserOpFeePerGas, prefundTokenPriceETH);

        // Refund the sender with the `acceptedToken` excess taken during the prefund in {_validatePaymasterUserOp}.
        // Note: Since we prefunded with `maxCost`, an invariant is: prefundTokenAmount >= actualTokenAmount.
        IERC20(token).trySafeTransfer(userOpSender, prefundTokenAmount - actualTokenAmount);
    }

    /// @dev Get the token price in ETH from the pool's current price.
    /// @param poolKey The pool key for the ETH/token pair
    /// @return tokenPriceInETH Price of 1 unit of token in ETH (scaled by _tokenPriceDenominator())
    function _getTokenPriceFromPool(PoolKey memory poolKey)
        internal
        view
        returns (uint256 tokenPriceInETH)
    {
        // Get the current sqrt price from the pool
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());

        // Ensure pool is initialized
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        // Get token decimals to properly scale the price
        uint8 tokenDecimals = IERC20Metadata(Currency.unwrap(poolKey.currency1)).decimals();

        // sqrtPriceX96 represents sqrt(price) where price = token1/token0
        // Since token0 is ETH (18 decimals) and token1 is the token (tokenDecimals),
        // price = (sqrtPriceX96 / 2^96)^2 gives us token1 amount per 1 token0
        // We want: how much token1 do we need to get 1 ETH worth of value

        // Calculate the actual price: token1 per token0
        uint256 priceX192 = Math.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1);

        // Convert to token price in ETH with proper scaling
        // price = (priceX192 / 2^192) * (10^18 / 10^tokenDecimals)
        // This gives us how many tokens equal 1 ETH
        return Math.mulDiv(
            priceX192,
            10 ** 18 * _tokenPriceDenominator(),
            (uint256(1) << 192) * 10 ** tokenDecimals
        );
    }

    /// @dev Calculates the cost of the user operation in ERC-20 tokens.
    /// @param cost Base cost in native currency
    /// @param feePerGas Fee per gas unit
    /// @param tokenPrice Price of token in native currency (scaled by _tokenPriceDenominator)
    /// @return Token amount required to cover the operation cost
    function _erc20Cost(uint256 cost, uint256 feePerGas, uint256 tokenPrice)
        internal
        view
        virtual
        returns (uint256)
    {
        return Math.mulDiv(cost + _postOpCost() * feePerGas, tokenPrice, _tokenPriceDenominator());
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

    /**
     * @dev Set the hook permissions, specifically `beforeInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`,
     * `beforeSwap`, and `afterSwap`
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory permissions)
    {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
