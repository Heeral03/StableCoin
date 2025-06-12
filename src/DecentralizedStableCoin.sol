// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

// Importing OpenZeppelin's ERC20 implementation with burn functionality
import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// Importing OpenZeppelin's Ownable contract to restrict certain functions to the owner (DSCEngine)
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/*
* @title: Decentralized Stable Coin
* @author: Heeral Mandolia
* @Collateral: Exogenous (ETH & BTC)
* @Minting: Algorithmic
* @Relative Stability: Pegged to USD
* @This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stable coin system.
*/
// Ownable is used to restrict `mint` and `burn` functions to only the DSCEngine (owner of this contract)
contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    // Error thrown when trying to mint or burn zero or negative amounts
    error DecentralizedStableCoin__MustBeMoreThanZero();

    // Error thrown when attempting to burn more tokens than the user holds
    error DecentralizedStableCoin__BurnAmountExceedsBalance();

    // Error thrown when minting to the zero address
    error DecentralizedStableCoin__NotZeroAddress();

    /**
     * @notice Constructor sets token name and symbol and sets initial owner (usually DSCEngine)
     * @dev `ERC20(...)` sets the name and symbol of the token
     * @dev `Ownable(msg.sender)` sets the deployer as the initial owner (can be changed later)
     */
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) { }

    /**
     * @notice Burn function for the stablecoin, only callable by the owner (DSCEngine)
     * @param _amount The amount of DSC to burn
     * @dev Reverts if amount is <= 0 or if user tries to burn more than they own
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        // Check for zero or negative burn amount
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        // Check for sufficient balance
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        // Call super to perform the actual burn
        super.burn(_amount);
    }

    /**
     * @notice Mint function for creating new DSC tokens, only callable by the owner (DSCEngine)
     * @param _to The recipient address
     * @param _amount The amount to mint
     * @return success Returns true if minting succeeds
     * @dev Reverts on zero address or non-positive amount
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        // Prevent minting to zero address
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }

        // Prevent minting zero or negative amounts
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        // Call internal _mint function from ERC20
        _mint(_to, _amount);
        return true;
    }
}
