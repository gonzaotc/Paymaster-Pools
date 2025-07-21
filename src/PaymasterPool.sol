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

contract PaymasterPool is PaymasterERC20, ERC7535 {
    error InvalidDepositAmount();

    error Disabled();

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

    // ---- PaymasterERC20 Abstract Functions ----

    /// @inheritdoc PaymasterERC20
    function _fetchDetails(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        override
        returns (uint256 validationData, IERC20 token, uint256 tokenPrice)
    {
        // TODO: Implement your token validation and pricing logic
        // For now, return basic values
        return (0, acceptedToken, 1e18); // Placeholder - implement proper oracle pricing
    }

    /// ------ Disable PaymasterCore functions ------

    function deposit() public payable override {
        revert Disabled();
    }

    function withdraw(address payable to, uint256 value) public override {
        revert Disabled();
    }

    function addStake(uint32 unstakeDelaySec) public payable override {
        revert Disabled();
    }

    function unlockStake() public override {
        revert Disabled();
    }

    function withdrawStake(address payable to) public override {
        revert Disabled();
    }

    function _authorizeWithdraw() internal view override {
        revert Disabled();
    }
}
