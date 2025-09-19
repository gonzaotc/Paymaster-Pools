// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";

// Permit2 imports
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {Permit2} from "permit2/Permit2.sol";

contract TestingUtils is Test {
    using StateLibrary for IPoolManager;

    // Permit2 constants
    bytes32 public constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    function _signPermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // Build the permit typehash (EIP-2612 standard)
        // forge-lint: disable-next-line
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        // Build the struct hash
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, token.nonces(owner), deadline)
        );

        // Build the final hash
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        // Sign the hash with the private key
        return vm.sign(privateKey, hash);
    }

    /**
     * @dev Signs a Permit2 AllowanceTransfer permit (flexible amount)
     * @param permit2 The Permit2 contract instance to get domain separator
     * @param privateKey The private key to sign with
     * @param permitSingle The PermitSingle struct to sign
     * @return signature The packed signature bytes (r, s, v)
     */
    function _signPermit2Allowance(
        Permit2 permit2,
        uint256 privateKey,
        IAllowanceTransfer.PermitSingle memory permitSingle
    ) internal view returns (bytes memory signature) {
        bytes32 domainSeparator = permit2.DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_SINGLE_TYPEHASH,
                keccak256(
                    abi.encode(
                        keccak256(
                            "PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
                        ),
                        permitSingle.details.token,
                        permitSingle.details.amount,
                        permitSingle.details.expiration,
                        permitSingle.details.nonce
                    )
                ),
                permitSingle.spender,
                permitSingle.sigDeadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function getAmountsForLiquidity(
        IPoolManager poolManager,
        PoolKey memory poolKey,
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper
    ) public view virtual returns (uint256 amount0, uint256 amount1) {
        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        return LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
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

}
