// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * 
 * @title DSC Engine
 * @author Heeral Mandolia
 * @notice The system is designed to be as minimal as possible and have the tokens maintain a 1 token== 1$ peg.
 * This stable coin has the properties:
 * Exogenous
 * Dollar pegged
 * Algo stable
 * 
 * It is similar to DAI if DAI had no governance, no fees and is only backed by WETH and WBTC
 * 
 * Our Dsc system should always be Over Collateralized. At no point should amount of All collateral < = the $ backed by value of All DSc
 * @notice This contract is the core of the DSC System. It handle all logic for minting, and redeeming DSC, as well as depositing & withdrawing
 * collateral.
 */

/** Suppose a person A:
 * Threshold to lets say 150%
 *  $100 Eth collateral-->drops to 74$
 *  50$ minted-->punished now due to undercollateralization
 *  UNDERCOLLATERALIZED!!!
 *  Punished now
 *  0$
 * Now person B:
 *  Pays 50$
 *  Gets all the 74$ collateral of A
 *  Gets the profit of 24$
 */
contract DSCEngine is ReentrancyGuard{
    ///////////////
    /// ERRORS ////
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__NotMinted();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    ///////////////
    /// TYPES ////
    //////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////////
    /// State Variables ////
    /////////////////////// 
    uint256 private constant ADDITIONAL_FEED_PRECISION=1e10;
    uint256 private constant PRECISION=1e18;
    uint256 private constant LIQUADATIONS_THRESHHOLD=50;
    uint256 private constant LIQUADATIONS_PRECISION=100;
    uint256 private constant MIN_HEALTH_FACTOR=1e18;
    uint256 private constant LIQUADATION_BONUS=10; //10% bonus
    mapping(address token => address priceFeed)private s_priceFeeds; 
    mapping(address user => mapping(address token =>uint256 amount))private s_collateralDeposited;
    mapping(address user=>uint256 amountDscMinted)private s_dscMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;


    ////////////////
    /// Events ////
    //////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount); 
    event CollateralRedeemed(address indexed from,address indexed to, address indexed token, uint256  amount);

    ///////////////
    //MODIFIERS///
    //////////////
    modifier moreThanZero(uint256 amount) { 
        if(amount==0)revert DSCEngine__NeedsMoreThanZero();
        _;
    }
    modifier  isAllowedToken(address token) {
        //TODO: check if token is allowed
        if(s_priceFeeds[token]==address(0)){
            revert DSCEngine__NotAllowedToken();
        }
        _;
    } 

    ///////////////
    // FUNCTIONS //
    //////////////
    constructor(address[] memory tokenAddresses,address[] memory priceFeedAddresses, address dscAddress){
        if(tokenAddresses.length!=priceFeedAddresses.length){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for(uint256 i=0; i<tokenAddresses.length;i++){
            s_priceFeeds[tokenAddresses[i]]=priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc=DecentralizedStableCoin(dscAddress);


    }

    ////////////////////////
    // External Function ///
    ///////////////////////

    /**
     * 
     * @param tokenCollateralAddress The address of token to deposit as collateral
     * @param amountCollateral The amount of colalteral deposited
     * @param amountDscToMint The amount of dsc to mint
     * @notice This function will deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress,
    uint256 amountCollateral,uint256 amountDscToMint) external{
            depositCollateral(tokenCollateralAddress,amountCollateral);
            mintDsc(amountDscToMint);

    }
    /**
     * 
     * @notice Follows CEI -->Checks, Effects , Interactions
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral Amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress,
    uint256 amountCollateral)
    public moreThanZero(amountCollateral) 
    isAllowedToken(tokenCollateralAddress)
    nonReentrant                                                                        //Checks-->happening at modifier level
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress]+=amountCollateral;   //Effects
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);  //Interactions
        bool success =IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral Amount of collateral to deposit
     * @param amountDscToBurn The amount of dsc to burn (burning the debt)
     * This function burns the dsc and redeems the collateral
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral,uint256 amountDscToBurn)
    external moreThanZero(amountCollateral){
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress,amountCollateral);
    }

    /**
     * to redeem collateral :
     * 1. health factor must be >1 after collateral is pulled
     *
     */
    function redeemCollateral(address tokenCollateralAddress,uint256 amountCollateral)
    public moreThanZero(amountCollateral)
    nonReentrant
    {
        _redeeemCollateral(msg.sender, msg.sender,tokenCollateralAddress,amountCollateral);

        _revertIfHealthFactorIsBroken(msg.sender);

        //$100 and mints 20$ worth DSC
        //Burn alll dsc and get collateral back
        // This will break health factor in this scenario
        //1. Burn DSC
        //2. redeem ETH
    }



    /**
     * @param amountDscToMint The amount of dsc that we want to mint
     * Check if collateral value is > Dsc amount to be minted
     */

    function mintDsc(uint256 amountDscToMint)
    public moreThanZero(amountDscToMint)
    nonReentrant{
        s_dscMinted[msg.sender]+=amountDscToMint;
        //if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);

        //actually mint DSC
        bool minted=i_dsc.mint(msg.sender,amountDscToMint);
        if(!minted){
            revert DSCEngine__NotMinted();
        }
    }

    function burnDsc(uint256 amount)public moreThanZero(amount){
        _burnDsc(amount,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //just a backup
    }

/*
* @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
* This is collateral that you're going to take from the user who is insolvent.
* In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
* @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
* @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
*
* @notice: You can partially liquidate a user.
* @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
* @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
to work.
* @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
anyone.
* For example, if the price of the collateral plummeted before anyone could be liquidated.
*/
    function liquidate(address collateral, address user, uint256 debtToCover)
    external 
    moreThanZero(debtToCover)
    nonReentrant
    {
        //need to check health factor of user
        uint256 startingUserHealthFactor=_healthFactor(user);
        if(startingUserHealthFactor >=MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        //Burn their DSC Debt
        //And take their collateral
        //140 $ of ETH deposited, 100$ DSC
        // Debt to cover: 100$ of Debt= how much ETH?
        uint256 tokenAmountFromDebtCovered=getTokenAmountFromUsd(collateral,debtToCover);    //suppose: 0.05
 
        //10% of bonus
        //so we are giving liquadator 110$ of weth for 100DSC
        uint256 bonusCollateral=(tokenAmountFromDebtCovered * LIQUADATION_BONUS)/LIQUADATIONS_PRECISION; 
        //0.05*0.1=0.005--->0.055
        uint256 totalCollateral=bonusCollateral+tokenAmountFromDebtCovered;
        _redeeemCollateral(user, msg.sender,collateral,totalCollateral);
        _burnDsc(debtToCover,user,msg.sender);

        //check for health factor
        uint256 endingUserHealthFactor=_healthFactor(user);
        if(endingUserHealthFactor<=startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

    }
    

    ///////////////////////////////////////
    // Private, Internal View  Function ///
    ////////////////////////////////////// 
    /**
     * Returns How close to liquadation a user is
     * If a user goes below 1 then then can get liquadated (ratio)
     * @param user  User that is minting
     */
    function _healthFactor(address user)internal view returns(uint256){
        //1. get total Dsc minted
        //2.total collateral value 
        
        (uint256 totalDscMinted, uint256 collteralValueInUsd)= _getAccountInformation(user);
        if (totalDscMinted == 0) {
        return type(uint256).max; // Means "perfect health", can't be liquidated
    }
        uint256 collateralAdjustedForThreshold= (collteralValueInUsd* LIQUADATIONS_THRESHHOLD)/LIQUADATIONS_PRECISION;
        return (collateralAdjustedForThreshold*PRECISION)/totalDscMinted;
    }

    function _getAccountInformation(address user) private 
    view returns(uint256 totalDscMinted,
    uint256 collteralValueInUsd){

        totalDscMinted=s_dscMinted[user];
        collteralValueInUsd=getAccountCollateralValue(user);

    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. check health factor
        //2. revert if not 

        uint256 userHealthFactor=_healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }

    function _redeeemCollateral(address from,address to,address tokenCollateralAddress, uint256 amountCollateral) 
    private{

        s_collateralDeposited[from][tokenCollateralAddress]-=amountCollateral;
        emit CollateralRedeemed(from,to,tokenCollateralAddress, amountCollateral);
        //check for health factor now
        //calculate health factor
        bool success=IERC20(tokenCollateralAddress).transfer(to,amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }

    }
    function _burnDsc(uint256 amountDscToBurn,address onBehalfOf, address dscFrom)
    private {

        s_dscMinted[onBehalfOf]-=amountDscToBurn;
        bool success=i_dsc.transferFrom(dscFrom,address(this),amountDscToBurn);
        if(!success){   
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);

    }
    ///////////////////////////////////////
    // Public, External View  Function ///
    ////////////////////////////////////// 
    function getAccountCollateralValue(address user)
    public  view returns(uint256 totalCollateralValueInUsd){
        //loop thru each colalteral token, get the amount deposited, and map it to the price to get USD value
        for(uint256 i=0;i<s_collateralTokens.length;i++){
            address token=s_collateralTokens[i];
            uint256 amount=s_collateralDeposited[user][token];
            totalCollateralValueInUsd+=getUsdValue(token,amount);
        }
        return totalCollateralValueInUsd;

    }
    function getUsdValue(address token,uint256 amount)
    public view returns(uint256){
        AggregatorV3Interface priceFeed=AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,)=priceFeed.staleCheckLatestRoundData();
        return ((uint256(price)*ADDITIONAL_FEED_PRECISION) *amount) /PRECISION;
    }

    function getTokenAmountFromUsd(address token,uint256 usdAmountInWei)
    public view returns(uint256 tokenAmount){
        //price of Eth
        //2000$ of ETH 
        //1000$ ---->1000/2000=0.5 ETH
        AggregatorV3Interface priceFeed=AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,)=priceFeed.staleCheckLatestRoundData();
        tokenAmount=(usdAmountInWei*PRECISION) / (uint256(price)*ADDITIONAL_FEED_PRECISION);
        return tokenAmount;
    }
    function getAccountInformation(address user) external view returns(uint256 totalDscMinted,
    uint256 collteralValueInUsd){
        (totalDscMinted, collteralValueInUsd)=_getAccountInformation(user);
        return (totalDscMinted,collteralValueInUsd);

    }
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }
    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }
    function getCollateralTokenPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];
    }
    

}