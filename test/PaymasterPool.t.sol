// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// External
import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// Internal
import {PaymasterFactory} from "src/pheriphery/PaymasterFactory.sol";
import {PaymasterRouter} from "src/pheriphery/PaymasterRouter.sol";
import {PaymasterPool} from "src/core/PaymasterPool.sol";
import {PaymasterPoolMock} from "test/mocks/PaymasterPoolMock.sol";
import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
import {TestUtils} from "test/TestUtils.sol";

contract PaymasterPoolTest is Test, TestUtils {
    EntryPoint public entryPoint;
    PaymasterFactory public paymasterFactory;
    PaymasterRouter public paymasterRouter;
    PaymasterPoolMock public paymasterPool;
    ERC20PermitMock public token;

    address sender;
    uint256 senderPrivateKey;
    address lp1;
    address lp2;

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
        paymasterPool = new PaymasterPoolMock(address(token));

        // generate sender address and private key for permit testing
        (sender, senderPrivateKey) = makeAddrAndKey("sender");

        // generate lp1 and lp2 addresses
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");

        // mint 100 tokens to the sender
        token.mint(sender, 100e18);

        // mint some ether to the lp1 and lp2
        vm.deal(lp1, 1e18);
        vm.deal(lp2, 1e18);
    }

    function test_singleLP_deposit() public {
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

    function test_multipleLP_deposit() public {
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

    function test_permit_success() public {
        // Setup permit parameters
        uint256 value = type(uint256).max;
        uint256 deadline = type(uint256).max;
        
        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            IERC20Permit(address(token)),
            sender, 
            address(paymasterPool), 
            value, 
            deadline,
            senderPrivateKey
        );
        
        // Verify that the permit call succeeds
        assertTrue(paymasterPool.attemptPermit(sender, address(paymasterPool), value, deadline, v, r, s));
        
        // Verify that the allowance was set correctly
        assertEq(token.allowance(sender, address(paymasterPool)), value);
    }

    function test_permit_double_spend_failure() public {
        // Setup permit parameters
        uint256 value = type(uint256).max;
        uint256 deadline = type(uint256).max;
        
        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            IERC20Permit(address(token)),
            sender, 
            address(paymasterPool), 
            value, 
            deadline,
            senderPrivateKey
        );
        
        // Verify that the permit call succeeds
        assertTrue(paymasterPool.attemptPermit(sender, address(paymasterPool), value, deadline, v, r, s));
        
        // Consume the permit again 
        assertFalse(paymasterPool.attemptPermit(sender, address(paymasterPool), value, deadline, v, r, s));
    }
}
