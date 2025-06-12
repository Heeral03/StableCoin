//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @dev Library for handling oracle-related operations (like from chainlink price feeds) in the Decentralized Stable Coin (DSC) system.
 * @author Heeral
 * If price is stale, function will revert and render the DscEngine unusable.
 * We want the DSCEngine to freeze if the price feed is not working properly.
 * If the chainlink network explodes and you have lots of money locked in the protocol, you can always withdraw your collateral.
 */
library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant TIMEOUT=3 hours;
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256,
    uint256,uint256,uint80){
        // Get the latest round data from the price feed
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if(secondsSinceLastUpdate > TIMEOUT){
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

}