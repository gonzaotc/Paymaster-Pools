// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract MintTokens is Script {
    function run() public {
        // Read environment variables
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        
        console.log("Token Address:", tokenAddress);
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Mint tokens to recipient
        ERC20Mock(tokenAddress).mint(recipient, amount);
        
        vm.stopBroadcast();
        
        console.log("Successfully minted %s tokens to %s", amount, recipient);
    }
}
