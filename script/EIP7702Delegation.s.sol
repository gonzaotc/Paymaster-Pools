// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {MinimalAccountEIP7702} from "test/mocks/accounts/MinimalAccountEIP7702.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract EIP7702Delegation is Script {
    function run() public {
        MinimalAccountEIP7702 account =
            MinimalAccountEIP7702(payable(vm.envAddress("ACCOUNT_ADDRESS")));
        address EOA = vm.envAddress("EOA_ADDRESS");
        uint256 EOAPrivateKey = vm.envUint("EOA_PRIVATE_KEY");

        vm.startBroadcast(EOA);

        vm.signAndAttachDelegation(address(account), EOAPrivateKey);

        // do anything to trigger the delegation
        address(0).call{value: 1}("");

        // get the EOA private key
        vm.stopBroadcast();
    }
}
