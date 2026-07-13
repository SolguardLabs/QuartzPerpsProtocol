// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { SignedMath } from "./SignedMath.sol";

/// @title FundingMath
/// @notice Funding index and account payment helpers.
library FundingMath {
    using SignedMath for int256;

    function pendingPayment(int128 sizeX18, int256 currentIndexX18, int256 lastIndexX18)
        internal
        pure
        returns (int256)
    {
        int256 indexDelta = currentIndexX18 - lastIndexX18;
        if (sizeX18 == 0 || indexDelta == 0) return 0;
        return (int256(sizeX18) * indexDelta) / int256(QuartzTypes.WAD);
    }

    function nextIndex(int256 currentIndexX18, int256 rateX18, uint256 elapsed)
        internal
        pure
        returns (int256 nextIndexX18, int256 deltaX18)
    {
        if (elapsed == 0 || rateX18 == 0) return (currentIndexX18, 0);
        deltaX18 = (rateX18 * int256(elapsed)) / int256(1 days);
        nextIndexX18 = currentIndexX18 + deltaX18;
    }

    function clampRate(int256 requestedRateX18, int256 maxRateX18) internal pure returns (int256) {
        uint256 maxAbs = maxRateX18.abs();
        if (requestedRateX18.abs() <= maxAbs) return requestedRateX18;
        return requestedRateX18 > 0 ? int256(maxAbs) : -int256(maxAbs);
    }

    function preview(
        int128 sizeX18,
        int256 currentIndexX18,
        int256 lastIndexX18,
        uint48 lastUpdated
    ) internal pure returns (QuartzTypes.FundingPreview memory result) {
        result.currentIndexX18 = currentIndexX18;
        result.lastIndexX18 = lastIndexX18;
        result.indexDeltaX18 = currentIndexX18 - lastIndexX18;
        result.payment = pendingPayment(sizeX18, currentIndexX18, lastIndexX18);
        result.lastUpdated = lastUpdated;
    }
}
