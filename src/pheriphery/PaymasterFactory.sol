// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {PaymasterPool} from "src/core/PaymasterPool.sol";

/**
 * @title PaymasterFactory
 * @author Gonzalo Othacehe
 * @notice A factory for creating paymaster pools
 */
contract PaymasterFactory {
    /**
     * @notice A mapping of accepted tokens to their corresponding paymaster pools
     * @dev In this first implementation, we only support one paymaster per token.
     * Futurely, we will support multiple paymasters per token with different fee structures.
     */
    mapping(address token => address paymaster) public paymasters;

    /**
     * @notice Emitted when a new paymaster pool is created
     * @param token Address of the ERC20 token for the new paymaster
     * @param paymaster Address of the newly created paymaster pool
     */
    event PaymasterCreated(address indexed token, address indexed paymaster);

    /**
     * @notice Thrown when a paymaster pool already exists for a given token
     */
    error PaymasterExists();

    /**
     * @notice Creates a new paymaster pool for a given token
     * @param token Address of the ERC20 token for which to create a paymaster
     * @return paymaster Address of the newly created paymaster pool
     */
    function createPaymaster(address token) external returns (address paymaster) {
        // Currently, we only support one paymaster per token.
        if (paymasters[token] != address(0)) revert PaymasterExists();

        paymaster = address(new PaymasterPool(token));
        paymasters[token] = paymaster;

        emit PaymasterCreated(token, paymaster);
    }
}
