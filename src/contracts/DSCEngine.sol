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
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintError();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 10 ** 10;
    uint256 private constant PRECISION = 10 ** 18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private _tokenPriceFeeds;
    mapping(address user => mapping(address token => uint256 collateralDeposited)) private _userTokenCollateralDeposited;
    mapping(address user => uint256 dscMinted) private userDSCMinted;
    address[] private _allowedCollateralTokens;
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
            _allowedCollateralTokens.push(tokenCollateralAddresses[i]);
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

    /**
     * @dev follows CEI pattern.
     * @param amountToMint the amount of DSC to mint.
     * @notice The collateral value must be higher than the minimum threshold.
     */
    function mintDSC(uint256 amountToMint) external moreThanZero(amountToMint) nonReentrant {
        // _userTokenCollateralDeposited[msg.sender];
        userDSCMinted[msg.sender] += amountToMint;

        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = _dsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintError();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

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

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralValuesInUsd) = _getAccountInformation(user);
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
