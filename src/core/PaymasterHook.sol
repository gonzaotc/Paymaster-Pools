// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC6909TokenSupply} from
    "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909TokenSupply.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {
    IPoolManager,
    BalanceDelta,
    ModifyLiquidityParams,
    SwapParams
} from "v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

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
    using StateLibrary for IPoolManager;
    using ERC4337Utils for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;

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
    /// Note that currency0 must always be native, as only [gas, token] pairs are supported.
    function _beforeInitialize(address, PoolKey calldata key, uint160)
        internal
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
    /// @return delta The delta of the liquidity position.
    /// Note that currency0 is always native, and currency1 is always the paymaster pool supported token.
    /// Note that ETH is kept deposited in the entry point, while the token is kept in the hook balance.
    function addLiquidity(AddLiquidityParams calldata params)
        public
        payable
        virtual
        onlyInitializedPool(params.poolKey)
        returns (BalanceDelta delta)
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
    /// @return delta The delta of the liquidity position.
    function removeLiquidity(RemoveLiquidityParams calldata params)
        public
        payable
        virtual
        returns (BalanceDelta delta)
    {
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
    /// both ETH and token are deposited into the PoolManager for in-range liquidity.
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        int24 currentTick = getCurrentTick(key);

        if (params.zeroForOne) {
            // User selling ETH for USDC, provide USDC liquidity BELOW current price
            // Token balance is already in the hook (from LP deposits)
            uint256 tokenBalance = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));

            int24 tickLower = currentTick - LIQUIDITY_TICK_OFFSET;
            int24 tickUpper = currentTick;
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                tokenBalance
            );

            _modifyLiquidity(key, tickUpper, tickLower, int256(liquidity));
        } else {
            // User selling USDC for ETH, provide ETH liquidity ABOVE current price

            // Withdraw ETH from EntryPoint
            uint256 ethBalance = entryPoint().balanceOf(address(this));
            entryPoint().withdrawTo(payable(address(this)), ethBalance);

            int24 tickLower = currentTick;
            int24 tickUpper = currentTick + LIQUIDITY_TICK_OFFSET;
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                ethBalance
            );

            _modifyLiquidity(key, tickUpper, tickLower, int256(liquidity));
        }

        int24 tickLower = params.zeroForOne ? currentTick - LIQUIDITY_TICK_OFFSET : currentTick;
        int24 tickUpper = params.zeroForOne ? currentTick : currentTick + LIQUIDITY_TICK_OFFSET;

        _modifyLiquidity(key, tickUpper, tickLower, int256(liquidity));

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @dev After swap, the liquidity is removed and the ETH is deposited back to the entry point.
    /// Additionally, any pending deltas must be settled.
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        uint128 hookLiquidity = _getHookLiquidity(key);

        if (hookLiquidity != 0) _modifyLiquidity(-int256(hookLiquidity));

        // Settle any pending deltas.
        _settlePendingDeltas(key);

        // Deposit ETH back to EntryPoint
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            entryPoint().depositTo{value: ethBalance}(address(this));
        }

        return (this.afterSwap.selector, 0);
    }

    /// Modify the hook-owned liquidity position.
    /// Requires the PoolManager to be unlocked due to the Flash Accounting model.
    function _modifyLiquidity(
        PoolKey calldata poolKey,
        int24 tickUpper,
        int24 tickLower,
        int256 liquidityDelta
    ) internal returns (BalanceDelta delta) {
        (delta,) = poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
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
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    /// @dev Convert ETH to shares, currently is 1:1 ETH:shares
    function ethToShares(uint256 eth) public view returns (uint256) {
        return eth;
    }

    /// @dev Computes the maximum amount of liquidity received for a given amount of currency0 and currency1.
    /// @TBD verify if the result is enough to provide all the liquidity held in the hook.
    function _amountsToLiquidity(PoolKey calldata poolKey, uint256 ethAmount, uint256 tokenAmount)
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
    function _getHookLiquidity(PoolKey calldata poolKey) internal view returns (uint128) {
        bytes32 positionKey = Position.calculatePositionKey(
            address(this), getTickLower(poolKey), getTickUpper(poolKey), bytes32(0)
        );
        return poolManager.getPositionLiquidity(poolKey.toId(), positionKey);
    }

    function _settlePendingDeltas(PoolKey calldata key) internal {
        _settlePendingDelta(key.currency0);
        _settlePendingDelta(key.currency1);
    }

    function _settlePendingDelta(Currency currency) internal virtual {
        int256 currencyDelta = poolManager.currencyDelta(address(this), currency);

        if (currencyDelta > 0) {
            currency.take(poolManager, address(this), currencyDelta.toUint256(), false);
            // _depositOnYieldSource(currency, currencyDelta.toUint256());
        }

        if (currencyDelta < 0) {
            // _withdrawFromYieldSource(currency, (-currencyDelta).toUint256());
            currency.settle(poolManager, address(this), (-currencyDelta).toUint256(), false);
        }
    }

    /// @dev Get the uint256 token ID for a pool key.
    function poolKeyTokenId(PoolKey calldata poolKey) public pure returns (uint256) {
        return uint256(PoolIdLibrary.unwrap(poolKey.toId()));
    }
}
