// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {EntryPointVault} from "src/core/EntryPointVault.sol";
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";

import {console} from "forge-std/console.sol";

contract Deposit is Script {
    function run() public {
        address depositor = vm.envAddress("DEPOSITOR_ADDRESS");
        UniswapPaymaster paymaster = UniswapPaymaster(payable(vm.envAddress("PAYMASTER_ADDRESS")));
        // uint256 depositorPrivateKey = vm.envUint("DEPOSITOR_PRIVATE_KEY");

        vm.startBroadcast();

        paymaster.deposit{value: 1e17}(1e17, depositor);

        vm.stopBroadcast();
    }
}