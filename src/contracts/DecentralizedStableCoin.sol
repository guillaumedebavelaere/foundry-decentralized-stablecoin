// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Guillaume Debavelaere
 * @notice A decentralized stable coin using wETH or wBTC as collateral.
 * @dev Collateral: exogenous (wETH or wBTC)
 * @dev Minting: algorithmic
 * @dev Relative stability: pegged to usd
 *
 * @dev This is the ERC20 implementation contract of our stablecoin system, meant to be governed by DSCEngine.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(to, amount);
        return true;
    }
}
