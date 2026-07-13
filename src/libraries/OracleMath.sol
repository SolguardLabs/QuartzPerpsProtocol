// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";

/// @title OracleMath
/// @notice Price normalization, deviation, and observation aggregation helpers.
library OracleMath {
    using FixedPointMath for uint256;

    struct Observation {
        uint256 priceX18;
        uint48 timestamp;
    }

    struct DeviationCheck {
        uint256 referencePriceX18;
        uint256 observedPriceX18;
        uint256 deviationX18;
        bool withinBounds;
    }

    function normalize(uint256 rawPrice, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return rawPrice;
        if (decimals < 18) return rawPrice * (10 ** (18 - decimals));
        return rawPrice / (10 ** (decimals - 18));
    }

    function denormalize(uint256 priceX18, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return priceX18;
        if (decimals < 18) return priceX18 / (10 ** (18 - decimals));
        return priceX18 * (10 ** (decimals - 18));
    }

    function isFresh(uint48 updatedAt, uint48 maxAge, uint256 timestamp)
        internal
        pure
        returns (bool)
    {
        return updatedAt != 0 && timestamp <= uint256(updatedAt) + maxAge;
    }

    function isBounded(QuartzTypes.PriceFeed memory feed, uint256 priceX18)
        internal
        pure
        returns (bool)
    {
        return feed.enabled && priceX18 >= feed.minPriceX18 && priceX18 <= feed.maxPriceX18;
    }

    function deviationX18(uint256 aX18, uint256 bX18) internal pure returns (uint256) {
        if (aX18 == bX18) return 0;
        uint256 high = aX18 > bX18 ? aX18 : bX18;
        uint256 low = aX18 > bX18 ? bX18 : aX18;
        if (high == 0) return 0;
        return ((high - low) * QuartzTypes.WAD) / high;
    }

    function deviationBps(uint256 aX18, uint256 bX18) internal pure returns (uint256) {
        return (deviationX18(aX18, bX18) * QuartzTypes.BPS) / QuartzTypes.WAD;
    }

    function checkDeviation(
        uint256 referencePriceX18,
        uint256 observedPriceX18,
        uint256 maxDeviationX18
    ) internal pure returns (DeviationCheck memory result) {
        result.referencePriceX18 = referencePriceX18;
        result.observedPriceX18 = observedPriceX18;
        result.deviationX18 = deviationX18(referencePriceX18, observedPriceX18);
        result.withinBounds = result.deviationX18 <= maxDeviationX18;
    }

    function arithmeticMean(Observation[] memory observations) internal pure returns (uint256) {
        if (observations.length == 0) return 0;
        uint256 sum;
        for (uint256 i = 0; i < observations.length; i++) {
            sum += observations[i].priceX18;
        }
        return sum / observations.length;
    }

    function timeWeightedAverage(Observation[] memory observations, uint48 endTime)
        internal
        pure
        returns (uint256)
    {
        if (observations.length == 0) return 0;
        if (observations.length == 1) return observations[0].priceX18;

        uint256 weightedSum;
        uint256 totalWeight;
        for (uint256 i = 0; i < observations.length; i++) {
            uint48 start = observations[i].timestamp;
            uint48 end = i + 1 == observations.length ? endTime : observations[i + 1].timestamp;
            if (end <= start) continue;
            uint256 weight = end - start;
            weightedSum += observations[i].priceX18 * weight;
            totalWeight += weight;
        }
        if (totalWeight == 0) return observations[observations.length - 1].priceX18;
        return weightedSum / totalWeight;
    }

    function winsorize(uint256 priceX18, uint256 lowerX18, uint256 upperX18)
        internal
        pure
        returns (uint256)
    {
        return FixedPointMath.clamp(priceX18, lowerX18, upperX18);
    }
}
