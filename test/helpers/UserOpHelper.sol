// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {IEntryPointExtra} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

/**
 * @title UserOpHelper
 * @notice Helper contract for constructing and signing UserOperations in tests
 */
contract UserOpHelper is Test {
    using ERC4337Utils for PackedUserOperation;
    using MessageHashUtils for bytes32;

    struct GasConfiguration {
        uint256 callGasLimit; // The amount of gas to allocate the main execution call
        uint256 verificationGasLimit; //The amount of gas to allocate for the verification step
        uint256 preVerificationGas; // Extra gas to pay the bundler
        uint256 paymasterVerificationGasLimit; // The amount of gas to allocate for the paymaster validation code (only if paymaster exists)
        uint256 paymasterPostOpGasLimit; // The amount of gas to allocate for the paymaster post-operation code (only if paymaster exists)
        uint256 maxFeePerGas; // Maximum fee per gas (similar to EIP-1559 max_fee_per_gas)
        uint256 maxPriorityFeePerGas; // Maximum priority fee per gas (similar to EIP-1559 max_priority_fee_per_gas)
    }

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
     * @dev Builds paymaster data for the UniswapPaymaster using Permit2 AllowanceTransfer
     */
    function buildPaymasterData(
        address paymaster,
        uint128 paymasterVerificationGasLimit,
        uint128 paymasterPostOpGasLimit,
        PoolKey memory poolKey,
        IAllowanceTransfer.PermitSingle memory permitSingle,
        bytes memory signature
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            paymaster,
            paymasterVerificationGasLimit,
            paymasterPostOpGasLimit,
            abi.encode(poolKey, permitSingle, signature)
        );
    }

    /**
     * @dev Signs a UserOperation with the given private key
     */
    function signUserOp(PackedUserOperation memory userOp, uint256 privateKey, address entryPoint)
        public
        view
        returns (PackedUserOperation memory signedUserOp)
    {
        bytes32 userOpHash = hash(userOp, entryPoint);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, userOpHash);

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


    function hash(PackedUserOperation memory self, address entrypoint) internal view returns (bytes32) {
        return IEntryPointExtra(entrypoint).getUserOpHash(self);
    }
}
