// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PaymasterPool} from "./PaymasterPool.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

contract PaymasterFactory {
    address public entryPoint;

    mapping(address token => address paymaster) public paymasters;

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    event PaymasterCreated(address token, address paymaster);

    error PaymasterExists();

    function createPaymaster(address token) external returns (address paymaster) {
        if (paymasters[token] != address(0)) revert PaymasterExists();

        paymaster = address(new PaymasterPool(token));
        paymasters[token] = paymaster;

        emit PaymasterCreated(token, paymaster);
    }
}

contract PaymasterRouter is PaymasterFactory {
    constructor(address _entryPoint) PaymasterFactory(_entryPoint) {}

    function paymasterDetails(address token)
        external
        view
        returns (address paymaster, uint256 deposit)
    {
        paymaster = paymasters[token];
        if (paymaster == address(0)) return (address(0), 0);

        IEntryPoint entryPoint = IEntryPoint(entryPoint);
        deposit = entryPoint.balanceOf(paymaster);

        return (paymaster, deposit);
    }
}
