// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {Permit2} from "permit2/Permit2.sol";

contract ApprovePermit is Script {
    function run() public {
        ERC20Mock token = ERC20Mock(vm.envAddress("TOKEN_ADDRESS"));
        Permit2 permit2 = Permit2(vm.envAddress("PERMIT2_ADDRESS"));
        address EOA = vm.envAddress("EOA_ADDRESS");

        vm.startBroadcast(EOA);

        token.approve(address(permit2), type(uint256).max);
        

        vm.stopBroadcast();
    }
}
