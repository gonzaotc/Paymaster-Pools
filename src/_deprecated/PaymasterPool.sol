// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// External
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC4337Utils,
    PackedUserOperation
} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

// Internal
import {ERC7535} from "src/ERC7535/ERC7535.sol";
import {MinimalPaymasterCore} from "src/core/MinimalPaymasterCore.sol";

/**
 * @title PaymasterPool
 * @author Gonzalo Othacehe
 * @notice A permissionless paymaster pool that allows users to access the Ethereum Protocol without
 *  ether, while enabling liquidity providers to earn a corresponding share of the fees.
 *
 * Conceptually: as the Uniswap protocol is an AMM that allows anyone to exchange tokens and LPs to
 *  provide the service while getting paid, think of PaymasterPools as an Automated Paymaster that allows
 *  users to get their user operations sponsored, and LPs to provide the service while getting paid.
 */
contract PaymasterPool is ERC7535, MinimalPaymasterCore {
    using ERC4337Utils for *;
    using Math for *;
    using SafeERC20 for IERC20;

    /**
     * @notice The ERC20 token accepted by this PaymasterPool for gas payments
     */
    IERC20 public immutable ACCEPTED_TOKEN;

    /**
     * @notice Emitted when a user operation is paid by this paymaster using the specified ERC-20 `token`.
     * @param userOpHash Hash of the user operation that was paid for
     * @param token Address of the ERC20 token used for payment
     * @param tokenAmount Amount of tokens charged for the operation
     * @param tokenPrice Price of the token in native currency (e.g., ETH)
     */
    event UserOperationPaid(
        bytes32 indexed userOpHash, address indexed token, uint256 tokenAmount, uint256 tokenPrice
    );

    /**
     * @notice Thrown when the PaymasterPool is not approved to spend the userOpSender's tokens
     */
    error PaymasterNotApproved();

    /**
     * @notice Thrown when the PaymasterPool receives ether directly
     */
    error ReceiveNotAllowed();

    /**
     * @notice Creates a new PaymasterPool for the specified ERC20 token
     * @param _acceptedToken Address of the ERC20 token this paymaster will accept
     */
    constructor(address _acceptedToken)
        ERC20(
            string.concat("Paymaster Pool ", IERC20Metadata(_acceptedToken).symbol()),
            string.concat("pp", IERC20Metadata(_acceptedToken).symbol())
        )
    {
        ACCEPTED_TOKEN = IERC20(_acceptedToken);
    }

    /**
     * @notice Rejects ether deposits to the PaymasterPool
     * @dev will convert this into a lp deposit later @TBD
     */
    receive() external payable {
        revert ReceiveNotAllowed();
    }

    /**
     * @notice Returns the total ether deposited into the ERC-4337 entryPoint that belongs to this PaymasterPool
     * @return Total assets (ETH) available for gas payments
     */
    function totalAssets() public view virtual override returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * @notice Deposits ether into the ERC-4337 entryPoint on behalf of this PaymasterPool
     * @param caller Address initiating the deposit
     * @param receiver Address receiving the shares
     * @param assets Amount of ETH being deposited
     * @param shares Amount of shares being minted
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        super._deposit(caller, receiver, assets, shares);
        entryPoint().depositTo{value: assets}(address(this));
    }

    /**
     * @notice Withdraws ether from the ERC-4337 entryPoint on behalf of this PaymasterPool
     * @param caller Address initiating the withdrawal
     * @param receiver Address receiving the ETH
     * @param owner Address owning the shares being burned
     * @param assets Amount of ETH being withdrawn
     * @param shares Amount of shares being burned
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        entryPoint().withdrawTo(payable(receiver), assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Validates a user operation for paymaster sponsorship by processing ERC20 permit and prefunding
     * @param userOp The user operation to validate
     * @param userOpHash Hash of the user operation
     * @param maxCost Maximum cost in native currency for the operation
     * @return context Encoded validation context for use in postOp
     * @return validationData ERC-4337 validation result (success/failure with optional time bounds)
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal override returns (bytes memory context, uint256 validationData) {
        // Decode the paymaster data in order to obtain the permit parameters.
        (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _decodePaymasterData(userOp.paymasterData());

        // Attempt to consume the permit which may have been consumed by a front-runner.
        _attemptPermit(userOp.sender, address(this), value, deadline, v, r, s);

        // Get the token price in native currency
        uint256 tokenPriceInETH = _acceptedTokenPriceInETH();

        // Convert the maxCost to the token amount.
        uint256 tokenAmount = _erc20Cost(maxCost, userOp.maxFeePerGas(), tokenPriceInETH);

        // Charge a fee for the lps @TBD

        // Attempt to refund the paymaster with the token
        bool success = ACCEPTED_TOKEN.trySafeTransferFrom(userOp.sender, address(this), tokenAmount);

        // If the prefund fails, return a failed validation data
        if (!success) return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);

        return (
            _encodeValidationContext(userOp.sender, tokenAmount, tokenPriceInETH),
            ERC4337Utils.SIG_VALIDATION_SUCCESS
        );
    }

    /**
     * @notice Refunds the sender with excess acceptedToken taken during prefunding
     * @param mode Post-operation mode (success/revert)
     * @param context Encoded validation context from _validatePaymasterUserOp
     * @param actualGasCost Actual gas cost of the user operation
     * @param actualUserOpFeePerGas Actual fee per gas paid by the operation
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        (address userOpSender, uint256 prefundTokenAmount, uint256 prefundTokenPriceETH) =
            _decodeValidationContext(context);

        // Calculate the actual token amount spent by the user operation.
        uint256 actualTokenAmount =
            _erc20Cost(actualGasCost, actualUserOpFeePerGas, prefundTokenPriceETH);

        // Refund the sender with the `acceptedToken` excess taken during the prefund in {_validatePaymasterUserOp}.
        // Note: Since we prefunded with `maxCost`, an invariant I01 is: prefundTokenAmount >= actualTokenAmount.
        ACCEPTED_TOKEN.trySafeTransfer(userOpSender, prefundTokenAmount - actualTokenAmount);
    }

    /**
     * @notice Attempts to consume a permit for the accepted token
     * @param owner The owner of the permit
     * @param spender The spender of the permit
     * @param value The value of the permit
     * @param deadline The deadline of the permit
     * @param v The v component of the permit
     * @param r The r component of the permit
     * @param s The s component of the permit
     * @return success Whether the permit was consumed successfully
     */
    function _attemptPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (bool success) {
        try IERC20Permit(address(ACCEPTED_TOKEN)).permit(owner, spender, value, deadline, v, r, s) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Queries the token price for the acceptedToken in ETH using USD-based pricing oracles
     * @dev @TBD once we add a external call here, we will need to avoid reverts in case of failure and return validation failed instead.
     * @return tokenPriceInETH Price of 1 unit of acceptedToken in wei (native currency)
     */
    function _acceptedTokenPriceInETH() internal view virtual returns (uint256 tokenPriceInETH) {
        // Get prices from oracles (both in USD with 8 decimals, assume Chainlink standard for now).
        uint256 tokenPriceInUSD = _queryTokenPriceInUSD();
        uint256 ethPriceInUSD = _queryEthPriceInUSD();

        // Get the token decimals.
        uint256 tokenDecimals = IERC20Metadata(address(ACCEPTED_TOKEN)).decimals();

        // Calculate the token price in ETH scaled by a {_tokenPriceDenominator()} factor to avoid fractional value loss.
        tokenPriceInETH = ((tokenPriceInUSD / 10 ** tokenDecimals) / (ethPriceInUSD / 1e18))
            * _tokenPriceDenominator();

        return tokenPriceInETH;
    }

    /**
     * @notice Queries the token price for the acceptedToken in USD
     * @dev @TBD once we add a external call here, we will need to avoid reverts in case of failure and return validation failed instead.
     * @return tokenPriceInUSD Price of 1 unit of acceptedToken in USD
     */
    function _queryTokenPriceInUSD() internal view virtual returns (uint256 tokenPriceInUSD) {
        // Get prices from oracles (both in USD with 8 decimals, assume Chainlink standard for now).
        tokenPriceInUSD = 1e8; // $1.00000000 for USDC (8 decimals)
    }

    /**
     * @notice Queries the ETH price in USD
     * @dev @TBD once we add a external call here, we will need to avoid reverts in case of failure and return validation failed instead.
     * @return ethPriceInUSD Price of 1 unit of ETH in USD
     */
    function _queryEthPriceInUSD() internal view virtual returns (uint256 ethPriceInUSD) {
        // Get prices from oracles (both in USD with 8 decimals, assume Chainlink standard for now).
        ethPriceInUSD = 2500e8; // $2500.00000000 for ETH (8 decimals)
    }

    /**
     * @notice Calculates the cost of the user operation in ERC-20 tokens.
     * @param cost Base cost in native currency
     * @param feePerGas Fee per gas unit
     * @param tokenPrice Price of token in native currency (scaled by _tokenPriceDenominator)
     * @return Token amount required to cover the operation cost
     */
    function _erc20Cost(uint256 cost, uint256 feePerGas, uint256 tokenPrice)
        internal
        view
        virtual
        returns (uint256)
    {
        return (cost + _postOpCost() * feePerGas).mulDiv(tokenPrice, _tokenPriceDenominator());
    }

    /**
     * @notice Over-estimates the cost of the post-operation logic.
     * @return Gas units estimated for postOp execution
     */
    function _postOpCost() internal view virtual returns (uint256) {
        return 30_000;
    }

    /**
     * @notice Denominator used for interpreting the tokenPrice to avoid precision loss.
     * @return Scaling factor for fixed-point token price calculations (1e18)
     */
    function _tokenPriceDenominator() internal view virtual returns (uint256) {
        return 1e18;
    }

    /**
     * @notice Encodes the paymaster permit parameters for inclusion in paymaster data.
     * @param value ERC20 token amount for permit
     * @param deadline Permit expiration timestamp
     * @param v ECDSA signature component v
     * @param r ECDSA signature component r
     * @param s ECDSA signature component s
     * @return Encoded permit parameters as bytes
     */
    function _encodePaymasterPermit(uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        virtual
        returns (bytes memory)
    {
        return abi.encodePacked(value, deadline, v, r, s);
    }

    /**
     * @notice Decodes the paymaster permit parameters from paymaster data.
     * @param paymasterData Encoded permit parameters from user operation
     * @return value ERC20 token amount for permit
     * @return deadline Permit expiration timestamp
     * @return v ECDSA signature component v
     * @return r ECDSA signature component r
     * @return s ECDSA signature component s
     */
    function _decodePaymasterData(bytes memory paymasterData)
        internal
        view
        virtual
        returns (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    {

    }

    /**
     * @notice Encodes the validation context for use in postOp phase.
     * @param userOpSender Address of the user operation sender
     * @param prefundTokenAmount Amount of tokens prefunded during validation
     * @param prefundTokenPriceInETH Token price used during validation
     * @return Encoded context for postOp refund calculation
     */
    function _encodeValidationContext(
        address userOpSender,
        uint256 prefundTokenAmount,
        uint256 prefundTokenPriceInETH
    ) internal view virtual returns (bytes memory) {
        return abi.encodePacked(userOpSender, prefundTokenAmount, prefundTokenPriceInETH);
    }

    /**
     * @notice Decodes the validation context from postOp context parameter.
     * @param context Encoded validation context from _validatePaymasterUserOp
     * @return userOpSender Address of the user operation sender
     * @return prefundTokenAmount Amount of tokens prefunded during validation
     * @return prefundTokenPriceInETH Token price used during validation
     */
    function _decodeValidationContext(bytes memory context)
        internal
        view
        virtual
        returns (address userOpSender, uint256 prefundTokenAmount, uint256 prefundTokenPriceInETH)
    {
        (userOpSender, prefundTokenAmount, prefundTokenPriceInETH) =
            abi.decode(context, (address, uint256, uint256));
    }
}
