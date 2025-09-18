// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {SignerERC7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerERC7702.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

// Test
// import {console} from "forge-std/console.sol";

contract MinimalAccountEIP7702 is Account, IERC1271, SignerERC7702 {
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        override
        returns (bytes4)
    {
        return _rawSignatureValidation(hash, signature)
            ? IERC1271.isValidSignature.selector
            : bytes4(0xffffffff);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyEntryPointOrSelf
    {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
