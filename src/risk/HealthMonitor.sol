// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FundingEngine } from "../core/FundingEngine.sol";
import { PositionBook } from "../core/PositionBook.sol";
import { AccountMath } from "../libraries/AccountMath.sol";
import { FundingMath } from "../libraries/FundingMath.sol";
import { OracleRouter } from "../oracle/OracleRouter.sol";
import { RiskEngine } from "./RiskEngine.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title HealthMonitor
/// @notice Keeper-oriented account health classifier with funding-aware previews.
contract HealthMonitor {
    enum HealthBand {
        Empty,
        Healthy,
        BelowInitial,
        BelowMaintenance,
        Insolvent
    }

    struct HealthReport {
        address trader;
        uint256 marketId;
        HealthBand storedBand;
        HealthBand fundingAdjustedBand;
        QuartzTypes.RiskSnapshot storedRisk;
        QuartzTypes.RiskSnapshot fundingAdjustedRisk;
        QuartzTypes.FundingPreview fundingPreview;
        uint256 fundingDeficit;
        bool staleOracle;
    }

    FundingEngine public immutable fundingEngine;
    PositionBook public immutable positionBook;
    OracleRouter public immutable oracleRouter;
    RiskEngine public immutable riskEngine;

    constructor(
        address fundingEngine_,
        address positionBook_,
        address oracleRouter_,
        address riskEngine_
    ) {
        fundingEngine = FundingEngine(fundingEngine_);
        positionBook = PositionBook(positionBook_);
        oracleRouter = OracleRouter(oracleRouter_);
        riskEngine = RiskEngine(riskEngine_);
    }

    function report(address trader, uint256 marketId)
        external
        view
        returns (HealthReport memory out)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        QuartzTypes.FundingState memory funding = fundingEngine.fundingState(marketId);

        out.trader = trader;
        out.marketId = marketId;
        out.fundingPreview = FundingMath.preview(
            position.size,
            funding.cumulativeFundingIndexX18,
            position.lastFundingIndexX18,
            funding.lastUpdated
        );
        out.storedRisk = riskEngine.previewRisk(marketId, position, price.priceX18);
        out.storedBand = classify(position, out.storedRisk);

        AccountMath.FundingApplication memory application =
            AccountMath.applyFunding(position, out.fundingPreview.payment);
        out.fundingDeficit = application.deficit;
        out.fundingAdjustedRisk =
            riskEngine.previewRisk(marketId, application.positionAfter, price.priceX18);
        out.fundingAdjustedBand = classify(application.positionAfter, out.fundingAdjustedRisk);
        out.staleOracle = block.timestamp > uint256(price.updatedAt) + price.maxAge;
    }

    function classify(QuartzTypes.Position memory position, QuartzTypes.RiskSnapshot memory risk)
        public
        pure
        returns (HealthBand)
    {
        if (!position.exists || position.size == 0) return HealthBand.Empty;
        if (risk.equity <= 0) return HealthBand.Insolvent;
        if (risk.liquidatable) return HealthBand.BelowMaintenance;
        if (!risk.initialMarginSatisfied) return HealthBand.BelowInitial;
        return HealthBand.Healthy;
    }

    function batchBands(address[] calldata traders, uint256 marketId)
        external
        view
        returns (HealthBand[] memory bands)
    {
        bands = new HealthBand[](traders.length);
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        for (uint256 i = 0; i < traders.length; i++) {
            QuartzTypes.Position memory position = positionBook.position(traders[i], marketId);
            QuartzTypes.Position memory adjusted = _fundingAdjusted(marketId, position);
            QuartzTypes.RiskSnapshot memory risk =
                riskEngine.previewRisk(marketId, adjusted, price.priceX18);
            bands[i] = classify(adjusted, risk);
        }
    }

    function needsKeeper(address trader, uint256 marketId) external view returns (bool) {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        if (!position.exists || position.size == 0) return false;
        position = _fundingAdjusted(marketId, position);
        QuartzTypes.RiskSnapshot memory risk =
            riskEngine.previewRisk(marketId, position, price.priceX18);
        return risk.liquidatable || !risk.initialMarginSatisfied;
    }

    function _fundingAdjusted(uint256 marketId, QuartzTypes.Position memory position)
        internal
        view
        returns (QuartzTypes.Position memory)
    {
        QuartzTypes.FundingState memory funding = fundingEngine.fundingState(marketId);
        QuartzTypes.FundingPreview memory preview = FundingMath.preview(
            position.size,
            funding.cumulativeFundingIndexX18,
            position.lastFundingIndexX18,
            funding.lastUpdated
        );
        AccountMath.FundingApplication memory application =
            AccountMath.applyFunding(position, preview.payment);
        return application.positionAfter;
    }
}
