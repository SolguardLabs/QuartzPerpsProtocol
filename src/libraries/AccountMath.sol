// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { MarginMath } from "./MarginMath.sol";
import { PositionMath } from "./PositionMath.sol";
import { SignedMath } from "./SignedMath.sol";

/// @title AccountMath
/// @notice Helper routines for account simulations and non-mutating margin projections.
library AccountMath {
    using FixedPointMath for uint256;

    struct MarginApplication {
        uint128 marginAfter;
        uint256 deficit;
        int256 appliedDelta;
    }

    struct FundingApplication {
        QuartzTypes.Position positionAfter;
        int256 payment;
        uint256 deficit;
        bool changed;
    }

    struct WithdrawalProjection {
        QuartzTypes.Position positionAfter;
        QuartzTypes.RiskSnapshot riskAfter;
        uint256 requested;
        uint256 withdrawable;
        bool accepted;
    }

    function applySignedMargin(uint128 margin, int256 delta)
        internal
        pure
        returns (MarginApplication memory result)
    {
        (uint256 remaining, uint256 deficit) = SignedMath.addDelta(margin, delta);
        result.marginAfter = _toUint128(remaining);
        result.deficit = deficit;
        result.appliedDelta = delta;
    }

    function applyFunding(QuartzTypes.Position memory position, int256 fundingPayment)
        internal
        pure
        returns (FundingApplication memory result)
    {
        result.positionAfter = position;
        result.payment = fundingPayment;
        result.changed = fundingPayment != 0;
        if (fundingPayment == 0 || position.size == 0) return result;

        if (fundingPayment > 0) {
            uint256 debit = uint256(fundingPayment);
            if (debit > position.margin) {
                result.positionAfter.margin = 0;
                result.deficit = debit - position.margin;
            } else {
                result.positionAfter.margin = _toUint128(uint256(position.margin) - debit);
            }
        } else {
            result.positionAfter.margin =
                _toUint128(uint256(position.margin) + uint256(-fundingPayment));
        }
    }

    function applyRealizedPnl(QuartzTypes.Position memory position, int256 realizedPnl)
        internal
        pure
        returns (QuartzTypes.Position memory next, uint256 deficit)
    {
        next = position;
        (uint256 marginAfter, uint256 shortfall) =
            PositionMath.marginAfterPnl(position.margin, realizedPnl);
        next.margin = _toUint128(marginAfter);
        next.realizedPnl += realizedPnl;
        deficit = shortfall;
    }

    function equityAfterFunding(
        QuartzTypes.Position memory position,
        int256 fundingPayment,
        uint256 priceX18
    ) internal pure returns (int256 accountEquity, uint256 deficit) {
        FundingApplication memory application = applyFunding(position, fundingPayment);
        accountEquity = MarginMath.equity(application.positionAfter, priceX18);
        deficit = application.deficit;
    }

    function withdrawableMargin(
        QuartzTypes.Position memory position,
        QuartzTypes.MarketConfig memory config,
        uint256 priceX18
    ) internal pure returns (uint256 withdrawable) {
        if (position.margin == 0) return 0;
        if (position.size == 0) return position.margin;
        QuartzTypes.RiskSnapshot memory snapshot =
            MarginMath.buildRiskSnapshot(0, position, config, priceX18);
        if (snapshot.equity <= int256(snapshot.initialMargin)) return 0;
        uint256 excess = uint256(snapshot.equity - int256(snapshot.initialMargin));
        if (excess > position.margin) return position.margin;
        return excess;
    }

    function projectWithdrawal(
        uint256 marketId,
        QuartzTypes.Position memory position,
        QuartzTypes.MarketConfig memory config,
        uint256 priceX18,
        uint256 requested
    ) internal pure returns (WithdrawalProjection memory projection) {
        uint256 available = withdrawableMargin(position, config, priceX18);
        projection.requested = requested;
        projection.withdrawable = available;
        projection.accepted = requested <= available;
        projection.positionAfter = position;
        if (requested <= position.margin) {
            projection.positionAfter.margin = _toUint128(uint256(position.margin) - requested);
        } else {
            projection.positionAfter.margin = 0;
            projection.accepted = false;
        }
        projection.riskAfter =
            MarginMath.buildRiskSnapshot(marketId, projection.positionAfter, config, priceX18);
        if (projection.positionAfter.size != 0 && !projection.riskAfter.initialMarginSatisfied) {
            projection.accepted = false;
        }
    }

    function positionLeverageX18(QuartzTypes.Position memory position, uint256 priceX18)
        internal
        pure
        returns (uint256)
    {
        uint256 notional = PositionMath.notional(position.size, priceX18);
        int256 accountEquity = MarginMath.equity(position, priceX18);
        if (notional == 0) return 0;
        if (accountEquity <= 0) return type(uint256).max;
        return notional.divWad(uint256(accountEquity));
    }

    function liquidationBufferX18(
        QuartzTypes.Position memory position,
        QuartzTypes.MarketConfig memory config,
        uint256 priceX18
    ) internal pure returns (int256) {
        QuartzTypes.RiskSnapshot memory snapshot =
            MarginMath.buildRiskSnapshot(0, position, config, priceX18);
        return snapshot.equity - int256(snapshot.maintenanceMargin);
    }

    function _toUint128(uint256 value) private pure returns (uint128) {
        if (value > type(uint128).max) revert();
        return uint128(value);
    }
}
