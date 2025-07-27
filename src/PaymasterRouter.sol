// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {PaymasterPool} from "./PaymasterPool.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

/**
 * @title PaymasterFactory
 * @author Gonzalo Othacehe
 * @notice A factory for creating paymaster pools
 */
contract PaymasterFactory {
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
     * @notice The canonical entry point for the account that forwards and validates user operations
     */
    address public entryPoint;

    /**
     * @notice A mapping of accepted tokens to their corresponding paymaster pools
     * @dev In this first implementation, we only support one paymaster per token.
     * Futurely, we will support multiple paymasters per token with different fee structures.
     */
    mapping(address token => address paymaster) public paymasters;

    /**
     * @notice Creates a new PaymasterFactory
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     */
    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

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

/**
 * @title PaymasterRouter
 * @author Gonzalo Othacehe
 * @notice A router for finding the path towards a paymaster pool with enough deposit to cover the user operation
 */
contract PaymasterRouter is PaymasterFactory {
    /**
     * @notice Creates a new PaymasterRouter
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     */
    constructor(address _entryPoint) PaymasterFactory(_entryPoint) {}

    /**
     * @notice Finds the paymaster pool for a given token
     * @param token The address of the token to find the paymaster pool for
     * @return paymaster The address of the paymaster pool
     * @return deposit The deposit amount of the paymaster pool
     */
    function findPaymasterPool(address token)
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
