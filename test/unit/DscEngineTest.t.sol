// SPDX-License-Identifier: MIT

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
contract DscEngineTest is Test{
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    DSCEngine dscEngine;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER=makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL=10 ether;
    uint256 public constant STARTING_ERC20_BALANCE=10 ether;
    function setUp() external{
        //deploy contracts
        deployer=new DeployDsc();
        (dsc, dscEngine, config) =deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,,)=config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);


    }
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
        
    }
    //////////////////////
    //Constructor Tests//
    /////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenAddressesLengthIsNotEqualToPriceFeedAddressesLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
    }
    ////////////////////////////
    //Events Emitted Tests/////
    ///////////////////////////
function testEventEmittedWhenCollateralIsDeposited() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

    vm.expectEmit(true, true, true, true);
    emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
}

    ///////////////
    //Price Tests//
    ///////////////
    function testGetUsdValue() public view{
        uint256 ethAmount=15e18;
        // 15e18 *2000/eth=30,000 e18
        uint256 expectedUsd=30000e18;
        uint256 actualUsd=dscEngine.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd,actualUsd);
    }
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount=100 ether;
        uint256 expectedWeth=0.05 ether;
        uint256 actualWeth=dscEngine.getTokenAmountFromUsd(weth,usdAmount);
        assertEq(expectedWeth,actualWeth);
    }
    ////////////////////////////
    //Deposit Collateral Tests//
    ///////////////////////////

    function testRevertsIfCollateralIsZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth,0);
        vm.stopPrank();


    }
    function testRevertsIfCollateralIsNotAllowed() public {
        ERC20Mock ranToken= new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken),AMOUNT_COLLATERAL);
        vm.stopPrank();
    }


function testRevertsIfTransferIsFailed() public {
    // Arrange
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    
    // Force transferFrom to fail by setting allowance to 0 after approval
    vm.mockCall(
        weth,
        abi.encodeWithSelector(IERC20.transferFrom.selector),
        abi.encode(false)
    );
    
    // Act/Assert
    vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
}



    function testCanDepositCollateralAndGetAccountInfo() public  depositedCollateral
    {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)=dscEngine.getAccountInformation(USER);
        uint256 totalExpectedDscMinted=0;
        uint256 expectedDepositedAmount=dscEngine.getTokenAmountFromUsd(weth,totalCollateralValueInUsd);
        assertEq(totalExpectedDscMinted,totalDscMinted);
        //comparing amount of collateral with expected deposited amount
        assertEq(AMOUNT_COLLATERAL,expectedDepositedAmount);
    }
function testDepositSuccess() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();

    uint256 actualDeposited = dscEngine.getTokenAmountFromUsd(weth,dscEngine.getAccountCollateralValue(USER));
    assertEq(actualDeposited, AMOUNT_COLLATERAL);
}
    ////////////////////////////
    //Mint DSC Tests////////////
    ///////////////////////////
    function testMintedSuccess() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth,AMOUNT_COLLATERAL);
        uint256 mintAmount=1 ether;
        dscEngine.mintDsc(mintAmount);
        (uint256 totalDscMinted,)=dscEngine.getAccountInformation(USER);
        assertEq(mintAmount,totalDscMinted);
        vm.stopPrank();
    }

    function testRevertsIfNotMinted()public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(DecentralizedStableCoin.mint.selector,USER,1000 ether),
            abi.encode(false)
        );
        vm.expectRevert(DSCEngine.DSCEngine__NotMinted.selector);
        dscEngine.mintDsc(1000 ether);
        vm.stopPrank();
    }
    function testMintRevertsIfAmountIsZero() public {
    vm.startPrank(USER);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dscEngine.mintDsc(0);
    vm.stopPrank();
    }
    ////////////////////////////
    //Burn DSC Tests////////////
    ///////////////////////////
     function testRevertsIfAmountIsZero() public{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
     }

function testBurnsSuccess() public {
    uint256 burnAmount = 1 ether;

    // Setup: Deposit collateral and mint DSC first
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    dscEngine.mintDsc(2 ether); // Mint equal to starting balance
    vm.stopPrank();

    uint256 initialBalance = dsc.balanceOf(USER);

    // Burn some DSC
    vm.startPrank(USER);
    dsc.approve(address(dscEngine), burnAmount);
    dscEngine.burnDsc(burnAmount);
    vm.stopPrank();

    // Assert balance and account info updated correctly
    assertEq(dsc.balanceOf(USER), initialBalance - burnAmount);
    (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
    assertEq(totalDscMinted, 2 ether - burnAmount);
}
    ////////////////////////////
    //Redeem Collateral Tests////
    ////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }
function testCanRedeemCollateral() public depositedCollateral {
    // Arrange
    uint256 redeemAmount = 1 ether;
    vm.startPrank(USER);

    // Mint a small amount of DSC so health factor calculation doesn't divide by zero
    dscEngine.mintDsc(1 ether);

    uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);

    // Act
    dscEngine.redeemCollateral(weth, redeemAmount);
    vm.stopPrank();

    // Assert
    uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);
    assertEq(finalBalance, initialBalance + redeemAmount);

    (, uint256 afterTotalCollateral) = dscEngine.getAccountInformation(USER);
    uint256 updatedCollateralValue = afterTotalCollateral;
    uint256 expectedUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL - redeemAmount);
    assertEq(updatedCollateralValue, expectedUsd);
}
function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
    uint256 redeemAmount = 1 ether;

    // Mint to avoid health factor revert
    vm.startPrank(USER);
    dscEngine.mintDsc(1 ether);
    
    // Expect the event
    vm.expectEmit(true, true, true, true);
    emit DSCEngine.CollateralRedeemed(USER, USER, weth, redeemAmount);

    // Act
    dscEngine.redeemCollateral(weth, redeemAmount);
    vm.stopPrank();
}
    /////////////////////////////////////
    //Redeem Collateral for DSC Tests////
    /////////////////////////////////////

function testMustRedeemMoreThanZero() public {
    vm.startPrank(USER);
    
    // Setup: deposit and mint so burn doesn't fail first
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    dscEngine.mintDsc(1 ether);

    // Approve enough DSC to burn
    dsc.approve(address(dscEngine), 1 ether);

    // Expect revert when redeeming zero collateral
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dscEngine.redeemCollateralForDsc(weth, 0, 1 ether);

    vm.stopPrank();
}
function testCanRedeemForDsc() public {
    uint256 mintAmount = 2 ether;
    uint256 redeemAmount = 1 ether;

    // Setup: deposit and mint
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    dscEngine.mintDsc(mintAmount);

    // Approve for burning
    dsc.approve(address(dscEngine), mintAmount);

    // Act
    dscEngine.redeemCollateralForDsc(weth, redeemAmount, mintAmount);
    vm.stopPrank();

    // Assert: balance increased by redeem amount
    uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);
    assertEq(finalBalance, redeemAmount);

    // Assert: DSC balance decreased
    uint256 dscBalance = dsc.balanceOf(USER);
    assertEq(dscBalance, 0);

    // Check remaining collateral
    (, uint256 remainingCollateralInUsd) = dscEngine.getAccountInformation(USER);
    uint256 expectedUsdValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL - redeemAmount);
    assertEq(remainingCollateralInUsd, expectedUsdValue);
}
    /////////////////////////////////////
    //Health Factor Tests////////////////
    /////////////////////////////////////
    function testProperlyReportsHealthFactor() public {
    uint256 mintAmount = 1 ether; // $1000 DSC

    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
    vm.stopPrank();

    uint256 healthFactor = dscEngine.getHealthFactor(USER);

    // $1000 minted with $20,000 collateral at 50% liquidation threshold
    // 20,000 * 0.5 = 10,000 min collateral required
    // health factor = 10,000 / 1,000 = 10 (in 1e18 precision = 10 ether)
    uint256 expectedHealthFactor = 10 ether; // which is 1e19
    assertEq(healthFactor, 1e22); // means 10.0 health factor
}

function testHealthFactorCanGoBelowOne() public depositedCollateral {
    // Mint $100 worth of DSC
    vm.startPrank(USER);
    dscEngine.mintDsc(100 ether); // Assuming DSC = $1
    vm.stopPrank();

    // Drop ETH price from $2000 to $18
    int256 ethUsdUpdatedPrice = 18e8; // $18, 8 decimals
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

    // Get health factor
    uint256 userHealthFactor = dscEngine.getHealthFactor(USER);

    // 10 ETH * $18 = $180 collateral * 0.5 = $90 effective
    // Debt is $100 → health factor = 90 / 100 = 0.9
    assertEq(userHealthFactor, 0.9 ether);
}
    ////////////////////////////
    // Liquidation Tests ///////
    ////////////////////////////
/// This test needs its own setup
function testMustImproveHealthFactorOnLiquidation() public {
    // Arrange - Setup
    uint256 amountToMint = 100 ether; // $100 DSC
    uint256 collateralToCover = 1 ether;
    address liquidator = makeAddr("liquidator");
    
    // Setup mock DSC that mints more debt
    MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
    
    // Setup engine with mock DSC - with renamed arrays
    address[] memory allowedTokens = new address[](1);
    address[] memory priceFeeds = new address[](1);
    allowedTokens[0] = weth;
    priceFeeds[0] = ethUsdPriceFeed;
    
    DSCEngine mockDsce = new DSCEngine(allowedTokens, priceFeeds, address(mockDsc));
    mockDsc.transferOwnership(address(mockDsce));

    // Arrange - User deposits collateral and mints DSC
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
    mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
    vm.stopPrank();

    // Arrange - Liquidator setup
    ERC20Mock(weth).mint(liquidator, collateralToCover);

    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
    uint256 debtToCover = 10 ether;
    mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
    mockDsc.approve(address(mockDsce), debtToCover);

    // Act - Simulate price drop
    int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

    // Assert - Expect revert due to no health factor improvement
    vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    mockDsce.liquidate(weth, USER, debtToCover);
    vm.stopPrank();
}
function testCantLiquidateGoodHealthFactor() public depositedCollateral {
    // Arrange
    uint256 amountToMint = 1 ether; // $1000 DSC (assuming $1 per DSC)
    address liquidator = makeAddr("liquidator");
    
    // User mints some DSC (health factor will be good)
    vm.startPrank(USER);
    dscEngine.mintDsc(amountToMint);
    vm.stopPrank();

    // Setup liquidator
    ERC20Mock(weth).mint(liquidator, AMOUNT_COLLATERAL);
    
    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    dsc.approve(address(dscEngine), amountToMint);

    // Act/Assert - Should revert since health factor is good
    vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
    dscEngine.liquidate(weth, USER, amountToMint);
    vm.stopPrank();

    // Verify health factor is still good
    uint256 healthFactor = dscEngine.getHealthFactor(USER);
    assertGt(healthFactor, 1e18); // Should be > 1.0
}


}