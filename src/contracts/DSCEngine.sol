// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
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
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__NotEnoughDSC(uint256 amountDSCMinted);
    error DSCEngine__MintError();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 10 ** 10;
    uint256 private constant PRECISION = 10 ** 18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 private constant MIN_HEALTH_FACTOR = 1 * PRECISION;

    mapping(address token => address priceFeed) private _tokenPriceFeeds;
    mapping(address user => mapping(address token => uint256 collateralDeposited)) private _userTokenCollateralDeposited;
    mapping(address user => uint256 dscMinted) private userDSCMinted;
    address[] private _allowedCollateralTokens;
    DecentralizedStableCoin private immutable _dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

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
            _allowedCollateralTokens.push(tokenCollateralAddresses[i]);
            unchecked {
                ++i;
            }
        }
        _dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @param tokenCollateralAddress the address of the collateral to deposit.
     * @param amountCollateral the amount of the collateral to deposit.
     * @param amountToMint the amount of DSC to mint.
     */
    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountToMint);
    }

    /**
     * @dev follows CEI pattern.
     * @param tokenCollateralAddress the address of the collateral to deposit.
     * @param amountCollateral the amount of the collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedTokenForCollateral(tokenCollateralAddress)
        nonReentrant
    {
        _userTokenCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress the address of the collateral to redeem.
     * @param amountCollateral the amount of the collateral to redeem.
     * @param amountDscToBurn the amount of DSC to burn.
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender); // redeemCollateral will revert if health factor is broken
    }

    /**
     * @dev follows CEI pattern.
     * @param amountToMint the amount of DSC to mint.
     * @notice The collateral value must be higher than the minimum threshold.
     */
    function mintDSC(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        userDSCMinted[msg.sender] += amountToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = _dsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintError();
        }
    }

    function burnDSC(uint256 amountToBurn) public moreThanZero(amountToBurn) nonReentrant {
        _burnDSC(amountToBurn, msg.sender, msg.sender);
    }

    /**
     * @param tokenCollateralAddress the address of the collateral to liquidate.
     * @param user the address of the user to liquidate. The user who has broken the health factor. Ther _health factor should be lower thane MIN_HEALTH_FACTOR.
     * @param debtToCover the amount of DSC to burn to cover the debt and improve the user's health factor.
     * @notice You can partially liquidate a user's debt.
     * @notice You will get a bonus for the debt you cover.
     * @notice This function working assumes the protocol will be roughly 200% over collateralized in order to cover the bonus.
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedTokenForCollateral(tokenCollateralAddress)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //uint256 tokenAmountFromDebtCovered = debtToCover * PRECISION / getUSDValue(tokenCollateralAddress, 1);
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _burnDSC(debtToCover, user, msg.sender);
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    function getAccountInformation()
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValuesInUsd)
    {
        (totalDSCMinted, totalCollateralValuesInUsd) = _getAccountInformation(msg.sender);
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 length = _allowedCollateralTokens.length;
        uint256 totalCollateralValueInUsd;
        for (uint256 i; i < length;) {
            address token = _allowedCollateralTokens[i];
            uint256 amount = _userTokenCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUSDValue(token, amount);
            unchecked {
                ++i;
            }
        }
        return totalCollateralValueInUsd;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_tokenPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_tokenPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /////////////////////////////////
    // Private & Internal functions
    /////////////////////////////////
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @param amountToBurn the amount of DSC to burn.
     * @param onBehalfOf the address of the user who is burning DSC.
     * @param dscFrom the address of the user who is sending DSC to burn.
     * @dev
     */
    function _burnDSC(uint256 amountToBurn, address onBehalfOf, address dscFrom) internal moreThanZero(amountToBurn) {
        if (amountToBurn > userDSCMinted[onBehalfOf]) {
            revert DSCEngine__NotEnoughDSC(userDSCMinted[onBehalfOf]);
        }

        userDSCMinted[onBehalfOf] -= amountToBurn;
        // transfer from user to this contract because dsc engine is the owner of dsc and the one allowed to burn
        IERC20(_dsc).safeTransferFrom(dscFrom, address(this), amountToBurn);
        _dsc.burn(amountToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        if (amountCollateral > _userTokenCollateralDeposited[from][tokenCollateralAddress]) {
            revert DSCEngine__NotEnoughCollateral();
        }
        _userTokenCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralValuesInUsd) = _getAccountInformation(user);
        if (totalDSCMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold =
            totalCollateralValuesInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValuesInUsd)
    {
        totalDSCMinted = userDSCMinted[user];
        totalCollateralValuesInUsd = getAccountCollateralValue(user);
    }
}
