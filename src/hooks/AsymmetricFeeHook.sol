// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseOverrideFee} from "@openzeppelin/uniswap-hooks/fee/BaseOverrideFee.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";

/// @title AsymmetricFeeHook
/// @notice A hook that applies asymmetric fees based on swap direction
///
/// Particularly useful for [ETH, Token] pools to make token→ETH swaps cheaper,
/// reducing costs for users of the `UniswapPaymaster`.
contract AsymmetricFeeHook is BaseOverrideFee {
    /// fee in the ether->token direction
    // foundry disable-next-line
    uint24 immutable feeZeroForOne;
    /// fee in the token->ether direction
    // foundry disable-next-line
    uint24 immutable feeOneForZero;

    constructor(IPoolManager _poolManager, uint24 _feeZeroForOne, uint24 _feeOneForZero)
        BaseOverrideFee(_poolManager)
    {
        feeZeroForOne = _feeZeroForOne;
        feeOneForZero = _feeOneForZero;
    }

    /// @dev Returns an asymmetric fee, where it depends on the direction of the swap.
    function _getFee(address, PoolKey calldata, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (uint24)
    {
        return params.zeroForOne ? feeZeroForOne : feeOneForZero;
    }
}
