// // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC private _deployDSC;
    DSCEngine private _dscEngine;
    DecentralizedStableCoin private _dsc;
    HelperConfig private _helperConfig;
    address private _weth;
    address private _wethUsdPriceFeed;
    address private _wbtcUsdPriceFeed;
    address private _user = makeAddr("user");
    address private _liquidator = makeAddr("liquidator");
    uint256 private _collateralToCover = 20 ether;
    uint256 private constant _STARTING_WETH_USER_BALANCE = 10 ether;

    function setUp() public {
        _deployDSC = new DeployDSC();
        (_dsc, _dscEngine, _helperConfig) = _deployDSC.run();
        (_wethUsdPriceFeed, _wbtcUsdPriceFeed, _weth,,) = _helperConfig.activeNetworkConfig();
        ERC20Mock(_weth).mint(_user, _STARTING_WETH_USER_BALANCE);
    }

    ////////////////////////////////////////
    // Constructor tests
    ////////////////////////////////////////
    address[] public tokenCollateralAddresses;
    address[] public priceFeeds;

    function testRevertIfTokenCollateralAddressesLengthDoesntMatchPriceFeeds() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__ArrayLengthMismatch.selector);
        tokenCollateralAddresses.push(_weth);

        priceFeeds.push(_wethUsdPriceFeed);
        priceFeeds.push(_wbtcUsdPriceFeed);

        new DSCEngine(tokenCollateralAddresses, priceFeeds, address(_dsc));
        vm.stopPrank();
    }

    ////////////////////////////////////////
    // Test DSCEngine.depositCollateral()
    ////////////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.depositCollateral(_weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotSupported() public {
        ERC20Mock unsupportedCollateral = new ERC20Mock("Unsupported", "Unsupported", address(this), 1000 ether);
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedTokenCollateral.selector);
        _dscEngine.depositCollateral(address(unsupportedCollateral), 1 ether);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotApproved() public {
        vm.startPrank(_user);
        vm.expectRevert("ERC20: insufficient allowance");
        _dscEngine.depositCollateral(_weth, 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateral() public {
        // Given
        vm.startPrank(_user);
        // No weth has been deposited yet as collateral
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 0 ether);
        // No DSC has been minted yet for the user
        assertEq(_dsc.balanceOf(_user), 0);
        // The user has approved 1 weth to be sepnt by the DSCEngine
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);

        // When
        _dscEngine.depositCollateral(_weth, 1 ether);

        // Then
        // 1 weth has been deposited as collateral
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 1 ether);
        // No DSC minted by the user yet
        assertEq(_dsc.balanceOf(_user), 0);

        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = _dscEngine.getAccountInformation();

        uint256 expectedTotalDSCMinted = 0; // No DSC minted yet
        uint256 expectedTotalCollateralValueInUsd = 2000e18; // 1 eth = 2000 USD (mocked eth price)
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);

        vm.stopPrank();
    }

    ////////////////////////////////////////
    // Test DSCEngine.redeemCollateral()
    ////////////////////////////////////////

    function testRedeemCollateralRevertsIfZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.redeemCollateral(_weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfNoCollateralDeposited() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughCollateral.selector);
        _dscEngine.redeemCollateral(_weth, 1);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfAmountGreaterThanCollateralDeposited() public {
        // Given
        vm.startPrank(_user);
        // User has deposited 1 weth as collateral
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);

        // When redeem 2 ether, expect revert
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughCollateral.selector);
        _dscEngine.redeemCollateral(_weth, 2 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralWhenNoDSCMinted() public {
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE);

        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - 1 ether);

        // When
        _dscEngine.redeemCollateral(_weth, 1 ether);

        // Then
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE);
        assertEq(_dsc.balanceOf(_user), 0);

        vm.stopPrank();
    }

    function testRedeemCollateralWhenDSCMintedRevertsIfHealthFactorBroken() public {
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE);

        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - 1 ether);

        _dscEngine.mintDSC(1 ether);

        // When
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        _dscEngine.redeemCollateral(_weth, 1 ether);

        // Then
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - 1 ether);
        assertEq(_dsc.balanceOf(_user), 1 ether);

        vm.stopPrank();
    }

    function testRedeemCollateralWhenDSCMinted() public {
        // Given
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE);

        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - 1 ether);

        _dscEngine.mintDSC(0.5 ether);

        // When
        _dscEngine.redeemCollateral(_weth, 0.2 ether);

        // Then
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - 0.8 ether);
        assertEq(_dsc.balanceOf(_user), 0.5 ether);

        vm.stopPrank();
    }

    function testRedeemCollateralForDSC() public {
        // Given
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE);

        uint256 depositCollateralAmount = 1 ether;
        ERC20Mock(_weth).approve(address(_dscEngine), depositCollateralAmount);
        _dscEngine.depositCollateral(_weth, depositCollateralAmount);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - depositCollateralAmount);

        uint256 amountDSCToMint = 0.5 ether;
        _dscEngine.mintDSC(amountDSCToMint);

        // When
        uint256 amountDSCToBurn = 0.3 ether;
        _dsc.approve(address(_dscEngine), amountDSCToBurn);
        uint256 collateralAmountRedeem = 0.2 ether;
        _dscEngine.redeemCollateralForDSC(_weth, collateralAmountRedeem, amountDSCToBurn);

        // Then
        assertEq(
            ERC20Mock(_weth).balanceOf(_user),
            _STARTING_WETH_USER_BALANCE - depositCollateralAmount + collateralAmountRedeem
        );
        assertEq(_dsc.balanceOf(_user), amountDSCToMint - amountDSCToBurn);

        vm.stopPrank();
    }

    ////////////////////////////////////////
    // Test DSCEngine.mintDSC()
    ////////////////////////////////////////

    function testMintDSCRevertsIfZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    function testMintDSCRevertsIfNoCollateralDeposited() public {
        vm.startPrank(_user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        _dscEngine.mintDSC(1);
        vm.stopPrank();
    }

    function testMintDSC() public {
        // Given
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0 ether);
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 0 ether);
        uint256 amountDSCToMint = 0.4 ether;
        // User has deposited 1 weth as collateral
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);

        _dscEngine.depositCollateral(_weth, 1 ether);

        // When
        _dscEngine.mintDSC(amountDSCToMint);

        // Then
        // 1 DSC has been minted for the user
        assertEq(_dsc.balanceOf(_user), amountDSCToMint);
        // 1 weth has been deposited as collateral
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 1 ether);

        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = _dscEngine.getAccountInformation();

        uint256 expectedTotalCollateralValueInUsd = 2000e18; // 1 eth = 2000 USD (mocked eth price)
        assertEq(totalDSCMinted, amountDSCToMint);
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);

        vm.stopPrank();
    }

    ////////////////////////////////////////
    // Test DSCEngine.burnDSC()
    ////////////////////////////////////////

    function testBurnDSCRevertsIfZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testBurnDSCRevertsIfNoDSCMinted() public {
        vm.startPrank(_user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughDSC.selector, 0));
        _dscEngine.burnDSC(1);
        vm.stopPrank();
    }

    function testBurnDSC() public {
        // Given
        vm.startPrank(_user);
        assertEq(_dsc.balanceOf(_user), 0 ether);
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 0 ether);

        uint256 amountDSCToMint = 0.4 ether;
        // User has deposited 1 weth as collateral
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);
        _dscEngine.mintDSC(amountDSCToMint);

        assertEq(_dsc.balanceOf(_user), 0.4 ether);

        // When
        _dsc.approve(address(_dscEngine), amountDSCToMint);
        _dscEngine.burnDSC(amountDSCToMint);

        // Then
        assertEq(_dsc.balanceOf(_user), 0 ether);
        assertEq(ERC20Mock(_weth).balanceOf(address(_dscEngine)), 1 ether);

        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = _dscEngine.getAccountInformation();

        uint256 expectedTotalCollateralValueInUsd = 2000e18; // 1 eth = 2000 USD (mocked eth price)
        assertEq(totalDSCMinted, 0 ether);
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);

        vm.stopPrank();
    }

    ////////////////////////////////////////
    // Test DSCEngine.liquidate()
    ////////////////////////////////////////

    function testLiquidateRevertsIfZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.liquidate(_weth, _user, 0);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfTokenCollateralNotAllowed() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedTokenCollateral.selector);
        _dscEngine.liquidate(makeAddr("tokenNotAllowed"), _user, 1 ether);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorIsOk() public {
        vm.startPrank(_user);
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateralAndMintDSC(_weth, 1 ether, 200 ether);
        uint256 healthFactor = _dscEngine.getHealthFactor();
        assertGt(healthFactor, 1 ether);
        vm.stopPrank();

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        _dscEngine.liquidate(_weth, _user, 1 ether);
    }

    function testLiquidateRevertsIfHealthFactorIsNotImproved() public {
        // Given
        vm.startPrank(_user);
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateralAndMintDSC(_weth, 1 ether, 1000 ether);
        uint256 healthFactorBefore = _dscEngine.getHealthFactor();
        assertGe(healthFactorBefore, 1 ether);

        // Given collateral price is down and the health factor is broken
        MockV3Aggregator(_wethUsdPriceFeed).updateAnswer(500 * 10 ** 8); // 500 usd
        uint256 healthFactorAfter = _dscEngine.getHealthFactor();
        assertLt(healthFactorAfter, 1 ether);
        vm.stopPrank();
        ERC20Mock(_weth).mint(_liquidator, 20 ether);
        vm.startPrank(_liquidator);
        ERC20Mock(_weth).approve(address(_dscEngine), 15 ether);
        _dscEngine.depositCollateralAndMintDSC(_weth, 15 ether, 2000 ether);

        // When
        _dsc.approve(address(_dscEngine), 400 ether);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        _dscEngine.liquidate(_weth, _user, 400 ether);

        vm.stopPrank();
    }

    function testLiquidate() public {
        uint256 amountCollateral = 10 ether; // 1 ether = mocked to 2000 USD
        uint256 amountToMint = 100 ether; // 100 DSC
        // Given
        vm.startPrank(_user);
        
        ERC20Mock(_weth).approve(address(_dscEngine), amountCollateral);
        _dscEngine.depositCollateralAndMintDSC(_weth, amountCollateral, amountToMint);
        
        uint256 healthFactorBefore = _dscEngine.getHealthFactor();
        assertGe(healthFactorBefore, 1 ether);

        // Given collateral price is down and the health factor is broken
        MockV3Aggregator(_wethUsdPriceFeed).updateAnswer(18 * 10 ** 8); // 1 ether = 18 usd
        uint256 healthFactorAfter = _dscEngine.getHealthFactor();

        assertLt(healthFactorAfter, 1 ether);
        vm.stopPrank();
        

        ERC20Mock(_weth).mint(_liquidator, _collateralToCover); // mint 20 ether to the liquidator

        vm.startPrank(_liquidator);
        ERC20Mock(_weth).approve(address(_dscEngine), _collateralToCover);
        // deposit 20 ether as collateral and mint 100 DSC
        _dscEngine.depositCollateralAndMintDSC(_weth, _collateralToCover, amountToMint);

        // When
        // approve 100 DSC to be spent by the DSCEngine
        _dsc.approve(address(_dscEngine), amountToMint);
        // liquidate 100 DSC
        _dscEngine.liquidate(_weth, _user, amountToMint);
        vm.stopPrank();
        // Then
        uint256 expectedLiquidatorWeth = _dscEngine.getTokenAmountFromUsd(_weth, amountToMint)
            + (_dscEngine.getTokenAmountFromUsd(_weth, amountToMint) / _dscEngine.getLiquidationBonus());

        assertEq(_dsc.balanceOf(_user), 100 ether);
        assertEq(_dsc.balanceOf(_liquidator), 0 ether);
        assertEq(ERC20Mock(_weth).balanceOf(_user), _STARTING_WETH_USER_BALANCE - amountCollateral);
        assertEq(ERC20Mock(_weth).balanceOf(_liquidator), expectedLiquidatorWeth);

        
    }

    ////////////////////////////////////////
    // Test DSCEngine.getHealthFactor()
    ////////////////////////////////////////

    function testGetHealthFactor() public {
        // Given
        vm.startPrank(_user);
        // User has deposited 1 weth as collateral
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);

        // When
        _dscEngine.mintDSC(1000 ether);

        // Then
        uint256 healthFactor = _dscEngine.getHealthFactor();

        assertEq(healthFactor, 1 ether);

        vm.stopPrank();
    }

    function testGetHealthFactorWhenNoDSCMinted() public {
        // Given
        vm.startPrank(_user);
        // User hasn't mint any DSC token.
        assertEq(_dsc.balanceOf(_user), 0);

        // When
        uint256 healthFactor = _dscEngine.getHealthFactor();

        // Then
        assertEq(healthFactor, type(uint256).max);

        vm.stopPrank();
    }

    /////////////////////////////////
    // Test DSCEngine.getUSDValue()
    /////////////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 5 ether;
        uint256 expectedUSDValue = ethAmount * 2000; // 10000 USD (2000 is the mocked ETH price feed value)
        uint256 usdValue = _dscEngine.getUSDValue(_weth, ethAmount);
        assertEq(usdValue, expectedUSDValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 10000e18; // 10000 USD
        uint256 expectedTokenAmount = usdAmount / 2000; // 5 ETH (2000 is the mocked ETH price feed value)
        uint256 tokenAmount = _dscEngine.getTokenAmountFromUsd(_weth, usdAmount);
        assertEq(tokenAmount, expectedTokenAmount);
    }

    function testGetAccountCollateralValue() public {
        // Given
        vm.startPrank(_user);
        // User has deposited 1 weth as collateral
        ERC20Mock(_weth).approve(address(_dscEngine), 1 ether);
        _dscEngine.depositCollateral(_weth, 1 ether);

        // When
        uint256 accountCollateralValue = _dscEngine.getAccountCollateralValue(_user);

        // Then
        assertEq(accountCollateralValue, 2000e18); // 2000 USD (2000 is the mocked ETH price feed value)

        vm.stopPrank();
    }
}
