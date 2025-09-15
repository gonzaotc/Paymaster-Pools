// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @title UserOpHelper
 * @notice Helper contract for constructing and signing UserOperations in tests
 */
contract UserOpHelper is Test {
    using ERC4337Utils for PackedUserOperation;
    using MessageHashUtils for bytes32;

    /**
     * @dev Constructs a basic UserOperation for testing
     */
    function buildUserOp(
        address sender,
        uint256 nonce,
        bytes memory callData,
        bytes memory paymasterAndData,
        uint256 verificationGasLimit,
        uint256 callGasLimit,
        uint256 preVerificationGas,
        uint256 maxPriorityFeePerGas,
        uint256 maxFeePerGas
    ) public pure returns (PackedUserOperation memory userOp) {
        userOp = PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(
                abi.encodePacked(uint128(verificationGasLimit), uint128(callGasLimit))
            ),
            preVerificationGas: preVerificationGas,
            gasFees: bytes32(abi.encodePacked(uint128(maxPriorityFeePerGas), uint128(maxFeePerGas))),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    /**
     * @dev Builds paymaster data for the UniswapPaymaster
     */
    function buildPaymasterData(
        address paymaster,
        uint128 paymasterVerificationGasLimit,
        uint128 paymasterPostOpGasLimit,
        PoolKey memory poolKey,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            paymaster,
            paymasterVerificationGasLimit,
            paymasterPostOpGasLimit,
            abi.encode(poolKey, value, deadline, v, r, s)
        );
    }

    /**
     * @dev Signs a UserOperation with the given private key
     */
    function signUserOp(PackedUserOperation calldata userOp, uint256 privateKey, address entryPoint)
        public
        view
        returns (PackedUserOperation memory signedUserOp)
    {
        bytes32 userOpHash = userOp.hash(entryPoint);
        bytes32 ethSignedMessageHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);

        return PackedUserOperation({
            sender: userOp.sender,
            nonce: userOp.nonce,
            initCode: userOp.initCode,
            callData: userOp.callData,
            accountGasLimits: userOp.accountGasLimits,
            preVerificationGas: userOp.preVerificationGas,
            gasFees: userOp.gasFees,
            paymasterAndData: userOp.paymasterAndData,
            signature: abi.encodePacked(r, s, v)
        });
    }
}
