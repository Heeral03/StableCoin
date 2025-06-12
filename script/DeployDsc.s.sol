// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
contract DeployDsc is Script{
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function run() external returns(DecentralizedStableCoin, DSCEngine, HelperConfig){
        HelperConfig helperConfig=new HelperConfig();

        (address wethUsdPriceFeed,
        address wbtcUsdPriceFeed,
        address weth,
        address wbtc,
        uint256 deployerKey )= helperConfig.activeNetworkConfig();
        tokenAddresses= [weth,wbtc];
        priceFeedAddresses=[wethUsdPriceFeed,wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        dsc=new DecentralizedStableCoin();
        dscEngine =new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc,dscEngine, helperConfig);

    }
}