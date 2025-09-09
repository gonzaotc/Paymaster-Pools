// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// External
import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// Internal
import {ERC20PermitMock} from "test/mocks/ERC20PermitMock.sol";
import {TestUtils} from "test/TestUtils.sol";
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";

contract PaymasterPoolTest is Test, TestUtils, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    EntryPoint public entryPoint;
    ERC20PermitMock public token;
    UniswapPaymaster public paymaster;

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

        // deploy the paymaster
        paymaster = new UniswapPaymaster(manager);

        // create a ERC20 with permit.
        token = new ERC20PermitMock();

        // approve the paymaster to spend the token
        token.approve(address(paymaster), type(uint256).max);

        deployFreshManager();

        (key,) = initPool(
            Currency.wrap(address(0)), // native currency
            Currency.wrap(address(token)), // token currency
            IHooks(address(0)), // hooks
            1000, // fee
            60, // tick spacing
            SQRT_PRICE_1_2 // sqrt price x96
        );

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

    function test_initPool() view public {
        assertEq(Currency.unwrap(key.currency0), address(0));
        assertEq(Currency.unwrap(key.currency1), address(token));
        assertEq(address(key.hooks), address(0));
        assertEq(key.fee, 1000);
        assertEq(key.tickSpacing, 60);
        
        // Verify the pool was initialized with the correct price
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(key.toId());
        assertEq(sqrtPriceX96, SQRT_PRICE_1_2);
    }


    function test_permit_success() public {
        // Setup permit parameters
        uint256 value = type(uint256).max;
        uint256 deadline = type(uint256).max;

        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            IERC20Permit(address(token)),
            sender,
            address(paymaster),
            value,
            deadline,
            senderPrivateKey
        );

        // Call permit directly on the token
        token.permit(sender, address(paymaster), value, deadline, v, r, s);

        // Verify that the allowance was set correctly
        assertEq(token.allowance(sender, address(paymaster)), value);
    }
}
