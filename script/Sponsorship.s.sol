// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {Permit2} from "permit2/Permit2.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {MinimalAccountEIP7702} from "test/mocks/accounts/MinimalAccountEIP7702.sol";
import {UserOpHelper} from "test/helpers/UserOpHelper.sol";
import {TestingUtils} from "test/helpers/TestingUtils.sol";
import {UniswapPaymaster} from "src/core/UniswapPaymaster.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {console} from "forge-std/console.sol";


contract Sponsorship is Script, UserOpHelper, TestingUtils {
    function run() public {
        ERC20Mock token = ERC20Mock(vm.envAddress("TOKEN_ADDRESS"));
        Permit2 permit2 = Permit2(vm.envAddress("PERMIT2_ADDRESS"));
        UniswapPaymaster paymaster = UniswapPaymaster(payable(vm.envAddress("PAYMASTER_ADDRESS")));
        EntryPoint entryPoint = EntryPoint(payable(vm.envAddress("ENTRYPOINT_ADDRESS")));
        address EOA = vm.envAddress("EOA_ADDRESS");
        uint256 EOAPrivateKey = vm.envUint("EOA_PRIVATE_KEY");
        address receiver = vm.envAddress("RECEIVER_ADDRESS");
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(vm.envAddress("CURRENCY0_ADDRESS")),
            currency1: Currency.wrap(vm.envAddress("CURRENCY1_ADDRESS")),
            fee: uint24(vm.envUint("FEE")),
            tickSpacing: int24(int256(vm.envUint("TICK_SPACING"))),
            hooks: IHooks(address(0))
        });
        address bundler = vm.envAddress("BUNDLER_ADDRESS");
        uint256 bundlerPrivateKey = vm.envUint("BUNDLER_PRIVATE_KEY");

        vm.startBroadcast(EOA);

        // 1. Create gasless permit2 signature for paymaster
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: type(uint160).max, // Large allowance
                expiration: uint48(block.timestamp + 1 hours), // 1 hour
                nonce: 0
            }),
            spender: address(paymaster), // Paymaster gets permission
            sigDeadline: uint48(block.timestamp + 1 hours) // 1 hour
        });
        console.log("Built permit single!");

        // 2. Sign the permit2 signature
        bytes memory signature = _signPermit2Allowance(permit2, EOAPrivateKey, permitSingle);
        console.log("Permit2 signed! ");

        // 3. Build gas configuration
        GasConfiguration memory gasConfig = GasConfiguration({
            preVerificationGas: 50_000, // Extra gas to pay the bundler operational costs such as bundle tx cost and entrypoint static code execution.
            verificationGasLimit: 75_000, // The amount of gas to allocate for the verification step
            paymasterVerificationGasLimit: 800_000, // The amount of gas to allocate for the paymaster validation code (only if paymaster exists)
            paymasterPostOpGasLimit: 50_000, // The amount of gas to allocate for the paymaster post-operation code (only if paymaster exists)
            callGasLimit: 50_000, // The amount of gas to allocate the main execution call
            maxPriorityFeePerGas: 1 gwei, // Maximum priority fee per gas (similar to EIP-1559 max_priority_fee_per_gas)
            maxFeePerGas: 1 gwei // Maximum fee per gas (similar to EIP-1559 max_fee_per_gas)
        });
        console.log("Built gas config!");

        // 4. Build paymaster data
        bytes memory paymasterData = buildPaymasterData(
            address(paymaster), // paymaster
            uint128(gasConfig.paymasterVerificationGasLimit), // verification gas limit
            uint128(gasConfig.paymasterPostOpGasLimit), // post-op gas limit
            key, // pool key
            permitSingle, // permit single
            signature // signature
        );
        console.log("Built paymaster data!");

        // 5. Build calldata
        bytes memory callData = abi.encodeWithSelector(
            MinimalAccountEIP7702.execute.selector,
            address(token),
            0,
            abi.encodeWithSelector(token.transfer.selector, receiver, 1e18)
        );
        console.log("Built call data!");

        // 6. Build UserOperation
        PackedUserOperation memory userOp = buildUserOp(
            EOA,
            MinimalAccountEIP7702(payable(EOA)).getNonce(),
            callData,
            paymasterData,
            gasConfig.verificationGasLimit,
            gasConfig.callGasLimit,
            gasConfig.preVerificationGas,
            gasConfig.maxPriorityFeePerGas,
            gasConfig.maxFeePerGas
        );
        console.log("Built user op!");

        // 7. Sign UserOperation
        userOp = signUserOp(userOp, EOAPrivateKey, address(entryPoint));
        console.log("Signed user op!");

        vm.stopBroadcast();

        console.log("Executing user op!");

        vm.startBroadcast(bundlerPrivateKey);
        // 8. Execute the user operation
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        IEntryPoint(address(entryPoint)).handleOps(userOps, payable(bundler));
        vm.stopBroadcast();
        console.log("User op executed!");

        uint256 bundlerBalanceAfter = bundler.balance;
        console.log("Bundler balance after: ", bundlerBalanceAfter);

        uint256 entrypointDepositAfter = entryPoint.balanceOf(address(paymaster));
        console.log("Entrypoint deposit after: ", entrypointDepositAfter);
    }
}
