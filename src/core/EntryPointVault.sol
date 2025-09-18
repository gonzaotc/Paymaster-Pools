// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title EntryPointVault
 * @author Gonzalo Othacehe  
 * @notice ERC-4626-style Vault for pooled ERC-4337 EntryPoint deposits
 * 
 * @dev Allows anyone to deposit native currency into the ERC-4337 EntryPoint and receive proportional shares
 * in return. Depositors can withdraw their funds at any time. Any profits generated are automatically distributed 
 * to share holders proportionally to their ownership. Inspired by and partially sharing interface with ERC-4626.
 */ 
contract EntryPointVault is ERC20 {
    using Math for uint256;

    error EntryPointVaultExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    error EntryPointVaultExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    error EntryPointVaultInvalidNativeAmount(uint256 assets, uint256 value);

    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor() ERC20("EntryPointVault", "EPV") {}

    function entryPoint() public view virtual returns (IEntryPoint) {
        return ERC4337Utils.ENTRYPOINT_V08;
    }

    function totalAssets() public view virtual returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function deposit(uint256 assets, address receiver) public virtual payable returns (uint256) {
        if (assets != msg.value) {
            revert EntryPointVaultInvalidNativeAmount(assets, msg.value);
        }

        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert EntryPointVaultExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        returns (uint256)
    {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert EntryPointVaultExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
    {
        entryPoint().depositTo{value: assets}(address(this));
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);   
        entryPoint().withdrawTo(payable(receiver), assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
