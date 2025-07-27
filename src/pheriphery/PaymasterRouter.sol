// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterFactory} from "src/pheriphery/PaymasterFactory.sol";

/**
 * @title PaymasterRouter
 * @author Gonzalo Othacehe
 * @notice A router for finding the path towards a paymaster pool with enough deposit to cover the user operation
 */
contract PaymasterRouter {
    /**
     * @notice The factory for creating paymaster pools
     */
    address public immutable PAYMASTER_FACTORY;

    /**
     * @notice Creates a new PaymasterRouter
     * @param _paymasterFactory Address of the PaymasterFactory contract
     */
    constructor(address _paymasterFactory) {
        PAYMASTER_FACTORY = _paymasterFactory;
    }

    /**
     * @notice Finds the paymaster pool for a given token
     * @dev Futurely, we will support multiple paymasters per token with different fee
     * structures, and the router will find the best quote for the user operation.
     * @param token The address of the token to find the paymaster pool for
     * @return paymaster The address of the paymaster pool
     * @return deposit The deposit amount of the paymaster pool
     */
    function findPaymasterPool(address token)
        external
        view
        returns (address paymaster, uint256 deposit)
    {
        // Query the paymaster factory for the paymaster pool for the given token
        paymaster = PaymasterFactory(PAYMASTER_FACTORY).paymasters(token);
        if (paymaster == address(0)) return (address(0), 0);

        // Query the entry point for the deposit amount of the paymaster pool
        deposit = IEntryPoint(entryPoint()).balanceOf(paymaster);

        return (paymaster, deposit);
    }

    /**
     * @notice Gets the canonical entry point for the account that forwards and validates user operations
     * @return The canonical entry point for the account that forwards and validates user operations
     */
    function entryPoint() public view virtual returns (IEntryPoint) {
        return ERC4337Utils.ENTRYPOINT_V08;
    }
}
