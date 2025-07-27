// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {PaymasterFactory} from "src/pheriphery/PaymasterFactory.sol";
import {PaymasterRouter} from "src/pheriphery/PaymasterRouter.sol";
import {PaymasterPool} from "src/core/PaymasterPool.sol";
import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

contract PaymasterPoolTest is Test {
    EntryPoint public entryPoint;
    PaymasterFactory public paymasterFactory;
    PaymasterRouter public paymasterRouter;
    PaymasterPool public paymasterPool;
    ERC20PermitMock public token;

    address sender = makeAddr("sender");
    address lp1 = makeAddr("lp1");
    address lp2 = makeAddr("lp2");

    function setUp() public {
        // deploy the entrypoint
        deployCodeTo(
            "account-abstraction/contracts/core/EntryPoint.sol",
            address(ERC4337Utils.ENTRYPOINT_V08)
        );
        entryPoint = EntryPoint(payable(address(ERC4337Utils.ENTRYPOINT_V08)));

        // deploy the factory
        paymasterFactory = new PaymasterFactory();

        // deploy the router
        paymasterRouter = new PaymasterRouter(address(paymasterFactory));

        // create a ERC20 with permit.
        token = new ERC20PermitMock();

        // create a pool for the token
        paymasterPool = new PaymasterPool(address(token));

        // mint 100 tokens to the sender
        token.mint(sender, 100e18);

        // mint some ether to the lp1 and lp2
        vm.deal(lp1, 1e18);
        vm.deal(lp2, 1e18);
    }

    function test_paymasterPool_singleLP_deposit() public {
        // verify the pool is empty (there is no paymasterPool deposit in the entrypoint)
        assertEq(paymasterPool.totalAssets(), 0);

        // verify that the ppDAI supply is 0
        assertEq(paymasterPool.totalSupply(), 0);

        // lp1 deposit 1 ether to the pool
        vm.prank(lp1);
        paymasterPool.deposit{value: 1e18}(1e18, lp1);

        // verify that pool now deposited 1 ether in the entrypoint
        assertEq(paymasterPool.totalAssets(), 1e18);

        // verify that the total supply of ppDAI is 1e18
        assertEq(paymasterPool.totalSupply(), 1e18);

        // verify the ppDAI balance of the lp1 is 1e18
        assertEq(paymasterPool.balanceOf(lp1), 1e18);
    }

    function test_paymasterPool_multipleLP_deposit() public {
        // lp1 deposit 1 ether to the pool
        vm.prank(lp1);
        paymasterPool.deposit{value: 1e18}(1e18, lp1);

        // lp2 deposit 1 ether to the pool
        vm.prank(lp2);
        paymasterPool.deposit{value: 1e18}(1e18, lp2);

        // verify the balance of the pool is 2 ether
        assertEq(paymasterPool.totalAssets(), 2e18);

        // verify the total supply of ppDAI is 2e18
        assertEq(paymasterPool.totalSupply(), 2e18);

        // verify the ppDAI balance of the lp1 is 1e18
        assertEq(paymasterPool.balanceOf(lp1), 1e18);

        // verify the ppDAI balance of the lp2 is 1e18
        assertEq(paymasterPool.balanceOf(lp2), 1e18);
    }
}
