// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { SignedMath } from "./SignedMath.sol";

/// @title PositionMath
/// @notice Position notional, average entry, and realized PnL calculations.
library PositionMath {
    using FixedPointMath for uint256;

    function absSize(int128 sizeX18) internal pure returns (uint256) {
        return uint256(sizeX18 < 0 ? -int256(sizeX18) : int256(sizeX18));
    }

    function notional(int128 sizeX18, uint256 priceX18) internal pure returns (uint256) {
        return absSize(sizeX18).mulWad(priceX18);
    }

    function unrealizedPnl(int128 sizeX18, uint256 entryPriceX18, uint256 markPriceX18)
        internal
        pure
        returns (int256)
    {
        if (sizeX18 == 0 || entryPriceX18 == 0) return 0;
        int256 priceDelta = SignedMath.toInt256(markPriceX18) - SignedMath.toInt256(entryPriceX18);
        return (int256(sizeX18) * priceDelta) / int256(QuartzTypes.WAD);
    }

    function realizedPnlForReduction(
        int128 sizeX18,
        uint256 entryPriceX18,
        uint256 markPriceX18,
        uint256 reducedSizeX18
    ) internal pure returns (int256) {
        uint256 currentSize = absSize(sizeX18);
        if (currentSize == 0 || reducedSizeX18 == 0) return 0;
        if (reducedSizeX18 > currentSize) revert();
        int256 totalPnl = unrealizedPnl(sizeX18, entryPriceX18, markPriceX18);
        return (totalPnl * SignedMath.toInt256(reducedSizeX18)) / SignedMath.toInt256(currentSize);
    }

    function nextEntryPrice(
        int128 oldSizeX18,
        uint256 oldEntryPriceX18,
        int128 sizeDeltaX18,
        uint256 executionPriceX18
    ) internal pure returns (uint256) {
        int256 nextSize = int256(oldSizeX18) + int256(sizeDeltaX18);
        if (nextSize == 0) return 0;
        if (oldSizeX18 == 0) return executionPriceX18;
        if (!SignedMath.sameDirection(oldSizeX18, sizeDeltaX18)) {
            uint256 oldAbs = absSize(oldSizeX18);
            uint256 deltaAbs = absSize(sizeDeltaX18);
            if (deltaAbs <= oldAbs) return oldEntryPriceX18;
            return executionPriceX18;
        }
        uint256 oldNotional = absSize(oldSizeX18).mulWad(oldEntryPriceX18);
        uint256 deltaNotional = absSize(sizeDeltaX18).mulWad(executionPriceX18);
        uint256 nextAbs = uint256(nextSize < 0 ? -nextSize : nextSize);
        return (oldNotional + deltaNotional).divWad(nextAbs);
    }

    function isIncrease(int128 oldSizeX18, int128 deltaX18) internal pure returns (bool) {
        int256 nextSize = int256(oldSizeX18) + int256(deltaX18);
        uint256 oldAbs = absSize(oldSizeX18);
        uint256 nextAbs = uint256(nextSize < 0 ? -nextSize : nextSize);
        return nextAbs > oldAbs;
    }

    function tradeDirectionForReduction(int128 sizeX18, uint128 amountX18)
        internal
        pure
        returns (int128)
    {
        if (sizeX18 > 0) return -int128(amountX18);
        return int128(amountX18);
    }

    function reduceSize(int128 sizeX18, uint128 amountX18) internal pure returns (int128) {
        uint256 currentAbs = absSize(sizeX18);
        if (amountX18 > currentAbs) revert();
        if (amountX18 == currentAbs) return 0;
        if (sizeX18 > 0) return sizeX18 - int128(amountX18);
        return sizeX18 + int128(amountX18);
    }

    function marginAfterPnl(uint256 margin, int256 pnl)
        internal
        pure
        returns (uint256 remainingMargin, uint256 deficit)
    {
        return SignedMath.addDelta(margin, pnl);
    }
}
