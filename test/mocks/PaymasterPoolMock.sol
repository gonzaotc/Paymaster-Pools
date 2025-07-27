// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PaymasterPool} from "src/core/PaymasterPool.sol";

contract PaymasterPoolMock is PaymasterPool {
    constructor(address acceptedToken) PaymasterPool(acceptedToken) {}

    function attemptPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bool success) {
        return _attemptPermit(owner, spender, value, deadline, v, r, s);
    }

    function acceptedTokenPriceInETH() public view returns (uint256) {
        return _acceptedTokenPriceInETH();
    }

    function queryTokenPriceInUSD() public view returns (uint256) {
        return _queryTokenPriceInUSD();
    }

    function queryEthPriceInUSD() public view returns (uint256) {
        return _queryEthPriceInUSD();
    }

    function erc20Cost(uint256 cost, uint256 feePerGas, uint256 tokenPrice)
        public
        view
        returns (uint256)
    {
        return _erc20Cost(cost, feePerGas, tokenPrice);
    }
}
