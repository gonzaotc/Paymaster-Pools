// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7535} from "./ERC7535.sol";
import {IERC7535} from "./IERC7535.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PaymasterCore} from "@openzeppelin/community-contracts/account/paymaster/PaymasterCore.sol";
import {PaymasterERC20} from
    "@openzeppelin/community-contracts/account/paymaster/PaymasterERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IPaymaster} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {MinimalPaymasterCore} from "./MinimalPaymasterCore.sol";

contract PaymasterPool is ERC7535, MinimalPaymasterCore {
    IERC20 public immutable acceptedToken;

    constructor(address _acceptedToken)
        ERC20(
            string.concat("Paymaster Pool ", IERC20Metadata(_acceptedToken).symbol()),
            string.concat("pp", IERC20Metadata(_acceptedToken).symbol())
        )
    {
        acceptedToken = IERC20(_acceptedToken);
    }

    /// @inheritdoc IERC7535
    function totalAssets() public view virtual override returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /// @inheritdoc ERC7535
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        super._deposit(caller, receiver, assets, shares);
        entryPoint().depositTo{value: assets}(address(this));
    }

    /// @inheritdoc ERC7535
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

    /// @inheritdoc MinimalPaymasterCore
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view override returns (bytes memory context, uint256 validationData) {
        // TODO: Implement validation logic
        return (bytes(""), 0);
    }

    /// @inheritdoc MinimalPaymasterCore
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        // TODO: Implement post-operation logic
    }

}
