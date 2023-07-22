// // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC private _deployDSC;
    DSCEngine private _dscEngine;
    DecentralizedStableCoin private _dsc;
    HelperConfig private _helperConfig;
    address private _weth;
    address private _user = makeAddr("user");

    function setUp() public {
        _deployDSC = new DeployDSC();
        (_dsc, _dscEngine, _helperConfig) = _deployDSC.run();
        (,, _weth,,) = _helperConfig.activeNetworkConfig();
    }

    ////////////////////////////////////////
    // Test DSCEngine.depositCollateral()
    ////////////////////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(_user);
        vm.expectRevert(DSCEngine.DSCEngine__RequiresMoreThanZero.selector);
        _dscEngine.depositCollateral(_weth, 0);
        vm.stopPrank();
    }

    /////////////////////////////////
    // Test DSCEngine.getUSDValue()
    /////////////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 5e18; // 5 ETH
        uint256 expectedUSDValue = ethAmount * 2000; // 10000 USD (2000 is the mocked ETH price feed value)
        uint256 usdValue = _dscEngine.getUSDValue(_weth, ethAmount);
        assertEq(usdValue, expectedUSDValue);
    }
}
