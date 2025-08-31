// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// External
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import {BaseCustomAccounting} from "@openzeppelin/uniswap-hooks/base/BaseCustomAccounting.sol";
import {ERC6909TokenSupply} from "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909TokenSupply.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Internal
import {ERC7535} from "src/ERC7535/ERC7535.sol";
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
    using ERC4337Utils for *;
    using Math for *;
    using SafeERC20 for IERC20;

    /// @dev When initializing the hook, the currency0 must be native.
    error OnlyNativeCurrency();

    /// @dev Liquidity was attempted to be added or removed via the `PoolManager` instead of the hook.
    error LiquidityOnlyViaHook();

    /// @dev The amount of native currency sent is not the same as the amount of native currency expected.
    error InvalidNativeAmount();

    /// @dev Pool was not initialized.
    error PoolNotInitialized();

    struct AddLiquidityParams {
        address sender;
        PoolKey poolKey;
        uint256 amount0;
        uint256 amount1;
    }

    struct RemoveLiquidityParams {
        address sender;
        PoolKey poolKey;
        uint256 amount0;
        uint256 amount1;
    }

    modifier onlyInitializedPool(PoolKey calldata poolKey) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
        _;
    }

    /// @dev Initialize the unique hook's pool key.
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (key.currency0 != Currency.wrap(address(0))) revert OnlyNativeCurrency();
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
    /// Note that currency0 is always ETH, and currency1 is always the pool accepted token.
    /// Note that ETH is kept deposited in the entry point, while the token is kept in the hook.
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        virtual
        onlyInitializedPool(params.poolKey)
        returns (BalanceDelta delta)
    {
        if (params.amount0 != msg.value) revert InvalidNativeAmount();

        // Deposit the native currency to the entry point
        entryPoint().depositTo{value: params.amount0}(address(this));

        // transfer currency1 (token) from the sender to the hook, allowance is required.
        IERC20(params.poolKey.currency1).transferFrom(params.sender, address(this), params.amount1);

        // mint liquidity shares to the sender
        _mint(params.sender, params.poolKey.toId(), ethToShares(msg.value));
    }

    /// @dev Convert ETH to shares, currently is 1:1 ETH:shares
    function ethToShares(uint256 eth) public view returns (uint256) {
        return eth;
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        payable
        virtual
        returns (BalanceDelta delta)
    {
        // burn liquidity shares
        _burn(params.sender, params.poolKey.toId(), ethToShares(params.amount0));

        // withdraw the native currency from the entry point to the sender
        entryPoint().withdrawTo(payable(params.sender), params.amount0);

        // transfer currency1 (token) from the hook to the sender. 
        IERC20(params.poolKey.currency1).transfer(params.sender, params.amount1);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Take the entire entrypoint deposit into the PoolManager.

        // 1. ask the entry point how much
        uint256 balance = entryPoint().balanceOf(address(this));

        // 2. get da money!
        entryPoint().withdrawTo(payable(address(this)), balance);

        // 3. put da money rowlling rowlling


        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        // Return the entire entrypoint deposit to the PoolManager.
        return (this.afterSwap.selector, 0);
    }

    /// Modify the hook-owned liquidity position.
    /// Requires the PoolManager to be unlocked due to the Flash Accounting model.
    /// @TBD: currently the liquidity is being added to the entire curve, but this may be 
    /// optimized by adding liquidity to a very small range. 
    function _modifyLiquidity(int256 liquidityDelta) internal returns (BalanceDelta delta) {
        (int24 tickLower, int24 tickUpper) = getClosestTickRange();

        (delta,) = poolManager.modifyLiquidity(
            _poolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /// @dev Returns the closest tick range to the current tick of the pool.
    /// Note that missaligned ticks to the pool tickSpacing will revert.
    function getClosestTickRange() public view virtual returns (int24 tickLower, int24 tickUpper) {
        int24 spacing = _poolKey.tickSpacing;
        (, int24 currentTick,,) = poolManager.getSlot0(_poolKey.toId());
        int24 floor = getTickFloor(currentTick, tickSpacing);

        return (floor, floor + tickSpacing);
    }

    /// @dev Returns the floor of the tick divided by the spacing.
    /// i.e. getTickFloor(33, 60) = 0, getTickFloor(63, 60) = 60, getTickFloor(120, 60) = 120
    /// getTickFloor(-1, 60) = -60, getTickFloor(-60, 60) = -60, getTickFloor(-120, 60) = -120
    function getTickFloor(int24 tick, int24 spacing) public pure returns (int24) {
        // spacing must be > 0 in Uniswap; assume invariant holds
        int24 q = tick / spacing; // truncates toward 0
        if (tick < 0 && (tick % spacing) != 0) q -= 1; // adjust to floor
        return q * spacing;
    }

    /// @dev Returns the lower tick boundary for the hook's liquidity position.
    function getTickLower() public view virtual returns (int24) {
        return TickMath.minUsableTick(_poolKey.tickSpacing);
    }

    /// @dev Returns the upper tick boundary for the hook's liquidity position.
    function getTickUpper() public view virtual returns (int24) {
        return TickMath.maxUsableTick(_poolKey.tickSpacing);
    }
}
