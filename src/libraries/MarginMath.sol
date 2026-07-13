// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { PositionMath } from "./PositionMath.sol";

/// @title MarginMath
/// @notice Initial margin, maintenance margin, health, and liquidation fee formulas.
library MarginMath {
    using FixedPointMath for uint256;

    function equity(QuartzTypes.Position memory position, uint256 priceX18)
        internal
        pure
        returns (int256)
    {
        return int256(uint256(position.margin))
            + PositionMath.unrealizedPnl(position.size, position.entryPriceX18, priceX18);
    }

    function initialMargin(uint256 notional, uint256 maxLeverageX18)
        internal
        pure
        returns (uint256)
    {
        if (notional == 0) return 0;
        return notional.divWadUp(maxLeverageX18);
    }

    function maintenanceMargin(uint256 notional, uint256 maintenanceMarginRatioX18)
        internal
        pure
        returns (uint256)
    {
        return notional.mulWadUp(maintenanceMarginRatioX18);
    }

    function liquidationFee(uint256 notional, uint256 liquidationFeeRatioX18)
        internal
        pure
        returns (uint256)
    {
        return notional.mulWad(liquidationFeeRatioX18);
    }

    function healthFactor(int256 accountEquity, uint256 maintenanceRequirement)
        internal
        pure
        returns (uint256)
    {
        if (maintenanceRequirement == 0) return type(uint256).max;
        if (accountEquity <= 0) return 0;
        return (uint256(accountEquity) * QuartzTypes.WAD) / maintenanceRequirement;
    }

    function buildRiskSnapshot(
        uint256 marketId,
        QuartzTypes.Position memory position,
        QuartzTypes.MarketConfig memory config,
        uint256 priceX18
    ) internal pure returns (QuartzTypes.RiskSnapshot memory snapshot) {
        uint256 positionNotional = PositionMath.notional(position.size, priceX18);
        int256 pnl = PositionMath.unrealizedPnl(position.size, position.entryPriceX18, priceX18);
        int256 accountEquity = int256(uint256(position.margin)) + pnl;
        uint256 initialRequirement = initialMargin(positionNotional, config.maxLeverageX18);
        uint256 maintenanceRequirement =
            maintenanceMargin(positionNotional, config.maintenanceMarginRatioX18);
        snapshot = QuartzTypes.RiskSnapshot({
            marketId: marketId,
            priceX18: priceX18,
            notional: positionNotional,
            initialMargin: initialRequirement,
            maintenanceMargin: maintenanceRequirement,
            liquidationFee: liquidationFee(positionNotional, config.liquidationFeeRatioX18),
            unrealizedPnl: pnl,
            equity: accountEquity,
            margin: position.margin,
            healthFactorX18: healthFactor(accountEquity, maintenanceRequirement),
            liquidatable: position.size != 0 && accountEquity < int256(maintenanceRequirement),
            initialMarginSatisfied: accountEquity >= int256(initialRequirement)
        });
    }
}
