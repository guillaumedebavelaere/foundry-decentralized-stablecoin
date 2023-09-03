//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
// Invariants

// 1. The total supply of DSC should be less than the total value of collateral.
// 2. Getter view functions should never revert.
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Handler} from "../fuzz/Handler.t.sol";
import {console} from "forge-std/console.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC private _deployDSC;
    DSCEngine private _dscEngine;
    DecentralizedStableCoin private _dsc;
    HelperConfig private _config;
    address private _weth;
    address private _wbtc;
    address private _wethUsdPriceFeed;
    address private _wbtcPricefeed;
    Handler private _handler;

    function setUp() external {
        _deployDSC = new DeployDSC();
        (_dsc, _dscEngine, _config) = _deployDSC.run();
        (_wethUsdPriceFeed, _wbtcPricefeed, _weth, _wbtc, ) = _config.activeNetworkConfig();
        _handler = new Handler(_dscEngine, _dsc);
        // targetContract(address(_dscEngine));
        targetContract(address(_handler));
    }

    function invariant_DSC_total_supply_should_be_less_than_total_collateral_value() public view {
        uint256 totalSupply = _dsc.totalSupply();

        uint256 totalWethDeposited = IERC20(_weth).balanceOf(address(_dscEngine));
        uint256 totalWbtcDeposited = IERC20(_wbtc).balanceOf(address(_dscEngine));

        uint256 wethValue = _dscEngine.getUSDValue(_weth, totalWethDeposited);
        uint256 wbtcValue = _dscEngine.getUSDValue(_wbtc, totalWbtcDeposited);

        uint256 totalCollateralValue = wethValue + wbtcValue;

        console.log("totalSupply: %s", totalSupply);
        console.log("totalCollateralValue: %s", totalCollateralValue);
    
        assert(totalSupply <= totalCollateralValue);
    }
}
