// SPDX-License-Identifier: MIT

//Have our invariants/ properties that our system holds
//What are the properties that we want to test?
// 1. Total supply of DSC should be less than total value of all collateral
// 2. Getter view functtion should never revert
pragma solidity ^0.8.18;
import {Test,console} from "../../lib/forge-std/src/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import{DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import{HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../../test/mocks/MockMoreDebtDSC.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {HandlerTest} from "./Handler.t.sol";
contract OpenTestInvariants is StdInvariant,Test{
    DeployDsc deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    HandlerTest handlerTest;
     function setUp() external {
        // Set up the environment for the invariants test
        // This could include deploying contracts, initializing state, etc.
       
        deployer = new DeployDsc();
        (dsc, dscEngine,config ) = deployer.run();
        (, ,weth, wbtc,) = config.activeNetworkConfig();
         handlerTest = new HandlerTest(dscEngine, dsc);
        // Set the target contract for invariants testing
        targetContract(address(handlerTest));
     }
     function invariant_protocolMustHaveMoreValueThanTotalSupply() external view {
        // Invariant: Total supply of DSC should be less than total value of all collateral
       //get the value of collateral in protocol
       //compare it to the debt
       uint256 totalSuply = dsc.totalSupply();
       uint256 totalWethDeposited=IERC20(weth).balanceOf(address(dscEngine));
       uint256 totalWbtcDeposited=IERC20(wbtc).balanceOf(address(dscEngine));
         uint256 totalCollateralValue = dscEngine.getUsdValue(weth,totalWethDeposited) + dscEngine.getUsdValue(wbtc,totalWbtcDeposited);
         console.log("Total WETH Deposited: %s", totalWethDeposited);
         console.log("Total WBTC Deposited: %s", totalWbtcDeposited);
         console.log("Total Supply of DSC: %s", totalSuply);
         console.log("Total Collateral Value: %s", totalCollateralValue);  
         console.log("Times Mint Is Called: %s", handlerTest.timesMintIsCalled());
         // Assert that the total supply of DSC is less than the total value of all collateral
         assert(totalCollateralValue >= totalSuply);


     }
       function invariant_getterFunctionsShouldNotRevert() external view {
         // Invariant: Getter view functions should never revert
         // This is a placeholder for the actual getter functions you want to test
         // For example, you might want to check the balance of a specific token or the total supply of DSC
         dscEngine.getCollateralTokens();
         dscEngine.getCollateralBalanceOfUser(address(this), weth);
         dscEngine.getCollateralBalanceOfUser(address(this), wbtc);
         dscEngine.getAccountInformation(address(this));
       }


}