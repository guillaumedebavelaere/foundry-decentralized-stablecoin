// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/contracts/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/contracts/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine private _dscEngine;
    DecentralizedStableCoin private _dsc;
    ERC20Mock _weth;
    ERC20Mock _wbtc;
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] usersWithCollateralDeposited;
    MockV3Aggregator private _ethUsdPriceFeed;

    constructor(DSCEngine dscEngine, DecentralizedStableCoin dsc) {
        _dscEngine = dscEngine;
        _dsc = dsc;
        address[] memory collateralAddresses = _dscEngine.getAllowedCollateralAddresses();
        _weth = ERC20Mock(collateralAddresses[0]);
        _wbtc = ERC20Mock(collateralAddresses[1]);
        _ethUsdPriceFeed = MockV3Aggregator(_dscEngine.getTokenPriceFeed(address(_weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(_dscEngine), amount);
        _dscEngine.depositCollateral(
            address(collateral),
            amount 
        );
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    // This breaks our invariants
    // function updateCollateralPrice(uint96 newPrice) external {
    //     _ethUsdPriceFeed.updateAnswer(int256(uint256(newPrice)));
    // }

    function mintDSC(uint256 amountToMint, uint256 adressSeed) external {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[adressSeed % usersWithCollateralDeposited.length];
        vm.startPrank(sender);
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = _dscEngine.getAccountInformation();
        int256 maxDSCToMint = int256(totalCollateralValueInUsd / 2) - int256(totalDSCMinted);
        if (maxDSCToMint <= 0) {
            return;
        }
        amountToMint = bound(amountToMint, 1, uint256(maxDSCToMint));
        _dscEngine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 amountMax =_dscEngine.getCollateralBalance(msg.sender, address(collateral));
        if (amountMax == 0) {
            return;
        }
        amount = bound(amount, 0, amountMax);
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        _dscEngine.redeemCollateral(
            address(collateral),
            amount
        );
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return _weth;
        } 
        return _wbtc;
    }
}
