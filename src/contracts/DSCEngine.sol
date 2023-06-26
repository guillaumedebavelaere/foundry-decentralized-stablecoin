// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DSCEngine
 * @author Guillaume Debavelaere
 * @notice The system is designed to maintain a 1 token == $1 peg.
 * @notice The stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically stable
 *
 * @notice It is similar to DAI if DAI had no governance, no fees, and was only
 * backed by WBTC and WETH.
 * Our DSC system should always be over collateralized. We
 * should always have more collateral in than DSC in $ value.
 * @dev This contract is the core of the DSC system. It handles all the logic for
 * mining, redeeming DSC, as well as depositing and withdrawing collateral.
 * @dev This contract is very loosely based  on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error DSCEngine__RequiresMoreThanZero();
    error DSCEngine__ArrayLengthMismatch();
    error DSCEngine__NotAllowedTokenCollateral();

    mapping(address token => address priceFeed) private _tokenPriceFeeds;
    mapping(address user => mapping(address token => uint256 collateralDeposited)) private _userTokenCollateralDeposited;
    DecentralizedStableCoin private immutable _dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__RequiresMoreThanZero();
        }
        _;
    }

    modifier isAllowedTokenForCollateral(address tokenAddress) {
        if (_tokenPriceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedTokenCollateral();
        }
        _;
    }

    constructor(address[] memory tokenCollateralAddresses, address[] memory priceFeeds, address dscAddress) {
        if (tokenCollateralAddresses.length != priceFeeds.length) {
            revert DSCEngine__ArrayLengthMismatch();
        }

        uint256 length = tokenCollateralAddresses.length;
        for (uint256 i; i < length;) {
            _tokenPriceFeeds[tokenCollateralAddresses[i]] = priceFeeds[i];
            unchecked {
                ++i;
            }
        }
        _dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @dev follows CEI pattern.
     * @param tokenCollateralAddress the address of the collateral to deposit.
     * @param amountCollateral the amount of the collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedTokenForCollateral(tokenCollateralAddress)
        nonReentrant
    {
        _userTokenCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
    }

    function redeemCollateral() external {}

    function depositCollateralAndMintDSC() external {}

    function redeemCollateralForDSC() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
