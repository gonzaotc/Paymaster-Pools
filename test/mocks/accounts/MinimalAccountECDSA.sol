// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {SignerECDSA} from "@openzeppelin/contracts/utils/cryptography/signers/SignerECDSA.sol";

// Test
import {console} from "forge-std/console.sol";

contract MinimalAccountECDSA is Account, EIP712, ERC7739, SignerECDSA {
    constructor(address signer) EIP712("MyAccount", "1") SignerECDSA(signer) {}

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
