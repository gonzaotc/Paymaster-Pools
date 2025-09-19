// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract MintTokens is Script {
    function run() public {
        // Use the token address from your config.env
        address token = 0xDc82c0362A241Aa94d53546648EACe48C9773dAa;
        address to = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        uint256 amount = 1e18;

        vm.startBroadcast();
        ERC20Mock(token).mint(to, amount);
        vm.stopBroadcast();

        console.log("Minted %s tokens to %s", amount, to);
    }
}
