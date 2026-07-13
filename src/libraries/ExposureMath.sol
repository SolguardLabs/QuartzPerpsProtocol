// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { PositionMath } from "./PositionMath.sol";
import { SignedMath } from "./SignedMath.sol";

/// @title ExposureMath
/// @notice Market-level open interest and skew projection utilities.
library ExposureMath {
    using FixedPointMath for uint256;

    struct ExposureCheck {
        QuartzTypes.MarketExposure projected;
        uint256 openInterestX18;
        uint256 utilizationX18;
        uint256 skewRatioX18;
        bool openInterestOk;
        bool skewOk;
    }

    function project(QuartzTypes.MarketExposure memory exposure, int128 oldSize, int128 nextSize)
        internal
        pure
        returns (QuartzTypes.MarketExposure memory projected)
    {
        projected = exposure;
        _remove(projected, oldSize);
        _add(projected, nextSize);
    }

    function check(
        QuartzTypes.MarketExposure memory exposure,
        QuartzTypes.MarketConfig memory config,
        int128 oldSize,
        int128 nextSize
    ) internal pure returns (ExposureCheck memory result) {
        result.projected = project(exposure, oldSize, nextSize);
        result.openInterestX18 =
            uint256(result.projected.longOpenInterestX18) + result.projected.shortOpenInterestX18;
        result.utilizationX18 = config.maxOpenInterestX18 == 0
            ? 0
            : result.openInterestX18.divWad(config.maxOpenInterestX18);
        result.skewRatioX18 = config.maxSkewX18 == 0
            ? 0
            : SignedMath.abs(result.projected.skewX18).divWad(config.maxSkewX18);
        result.openInterestOk = result.openInterestX18 <= config.maxOpenInterestX18;
        result.skewOk = SignedMath.abs(result.projected.skewX18) <= config.maxSkewX18;
    }

    function sideOpenInterest(QuartzTypes.MarketExposure memory exposure, bool longSide)
        internal
        pure
        returns (uint256)
    {
        return longSide ? exposure.longOpenInterestX18 : exposure.shortOpenInterestX18;
    }

    function dominantSide(QuartzTypes.MarketExposure memory exposure)
        internal
        pure
        returns (int256)
    {
        if (exposure.longOpenInterestX18 > exposure.shortOpenInterestX18) return 1;
        if (exposure.shortOpenInterestX18 > exposure.longOpenInterestX18) return -1;
        return 0;
    }

    function netUtilization(QuartzTypes.MarketExposure memory exposure, uint256 maxSkewX18)
        internal
        pure
        returns (uint256)
    {
        if (maxSkewX18 == 0) return 0;
        return SignedMath.abs(exposure.skewX18).divWad(maxSkewX18);
    }

    function grossUtilization(
        QuartzTypes.MarketExposure memory exposure,
        uint256 maxOpenInterestX18
    ) internal pure returns (uint256) {
        if (maxOpenInterestX18 == 0) return 0;
        uint256 gross = uint256(exposure.longOpenInterestX18) + exposure.shortOpenInterestX18;
        return gross.divWad(maxOpenInterestX18);
    }

    function makerImbalancePenaltyX18(
        QuartzTypes.MarketExposure memory exposure,
        uint256 skewScaleX18,
        uint256 maxPenaltyX18
    ) internal pure returns (uint256) {
        if (skewScaleX18 == 0 || maxPenaltyX18 == 0) return 0;
        uint256 skewRatio = SignedMath.abs(exposure.skewX18).divWad(skewScaleX18);
        if (skewRatio > QuartzTypes.WAD) skewRatio = QuartzTypes.WAD;
        return maxPenaltyX18.mulWad(skewRatio);
    }

    function projectedNotional(int128 oldSize, int128 delta, uint256 priceX18)
        internal
        pure
        returns (uint256 oldNotional, uint256 nextNotional)
    {
        int128 nextSize = SignedMath.checkedInt128(int256(oldSize) + int256(delta));
        oldNotional = PositionMath.notional(oldSize, priceX18);
        nextNotional = PositionMath.notional(nextSize, priceX18);
    }

    function _remove(QuartzTypes.MarketExposure memory exposure, int128 size) private pure {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure.longOpenInterestX18 -= amount;
            exposure.skewX18 -= size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure.shortOpenInterestX18 -= amount;
            exposure.skewX18 -= size;
        }
    }

    function _add(QuartzTypes.MarketExposure memory exposure, int128 size) private pure {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure.longOpenInterestX18 += amount;
            exposure.skewX18 += size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure.shortOpenInterestX18 += amount;
            exposure.skewX18 += size;
        }
    }
}
