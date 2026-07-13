// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FundingEngine } from "../core/FundingEngine.sol";
import { PositionBook } from "../core/PositionBook.sol";
import { FundingMath } from "../libraries/FundingMath.sol";
import { OracleRouter } from "../oracle/OracleRouter.sol";
import { RiskEngine } from "../risk/RiskEngine.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title QuartzLens
/// @notice Read-only account, market, and funding projections.
contract QuartzLens {
    OracleRouter public immutable oracleRouter;
    FundingEngine public immutable fundingEngine;
    RiskEngine public immutable riskEngine;
    PositionBook public immutable positionBook;

    struct MarketView {
        uint256 marketId;
        QuartzTypes.MarketConfig config;
        QuartzTypes.PriceData price;
        QuartzTypes.FundingState funding;
        QuartzTypes.MarketExposure exposure;
    }

    constructor(
        address oracleRouter_,
        address fundingEngine_,
        address riskEngine_,
        address positionBook_
    ) {
        oracleRouter = OracleRouter(oracleRouter_);
        fundingEngine = FundingEngine(fundingEngine_);
        riskEngine = RiskEngine(riskEngine_);
        positionBook = PositionBook(positionBook_);
    }

    function account(address trader, uint256 marketId)
        external
        view
        returns (QuartzTypes.AccountSnapshot memory snapshot)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory stored = positionBook.position(trader, marketId);
        QuartzTypes.FundingState memory funding = fundingEngine.fundingState(marketId);
        QuartzTypes.FundingPreview memory preview = FundingMath.preview(
            stored.size,
            funding.cumulativeFundingIndexX18,
            stored.lastFundingIndexX18,
            funding.lastUpdated
        );

        QuartzTypes.Position memory afterFunding = _applyFundingPreview(stored, preview.payment);
        snapshot = QuartzTypes.AccountSnapshot({
            trader: trader,
            marketId: marketId,
            position: stored,
            price: price,
            funding: preview,
            riskBeforeFunding: riskEngine.previewRisk(marketId, stored, price.priceX18),
            riskAfterFunding: riskEngine.previewRisk(marketId, afterFunding, price.priceX18)
        });
    }

    function market(uint256 marketId) external view returns (MarketView memory view_) {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        view_ = MarketView({
            marketId: marketId,
            config: config,
            price: oracleRouter.getPrice(config.oracleId),
            funding: fundingEngine.fundingState(marketId),
            exposure: positionBook.exposure(marketId)
        });
    }

    function pendingFunding(address trader, uint256 marketId)
        external
        view
        returns (QuartzTypes.FundingPreview memory)
    {
        QuartzTypes.Position memory stored = positionBook.position(trader, marketId);
        QuartzTypes.FundingState memory funding = fundingEngine.fundingState(marketId);
        return FundingMath.preview(
            stored.size,
            funding.cumulativeFundingIndexX18,
            stored.lastFundingIndexX18,
            funding.lastUpdated
        );
    }

    function _applyFundingPreview(QuartzTypes.Position memory position, int256 payment)
        internal
        pure
        returns (QuartzTypes.Position memory adjusted)
    {
        adjusted = position;
        if (payment > 0) {
            uint256 debit = uint256(payment);
            adjusted.margin =
                debit >= adjusted.margin ? 0 : uint128(uint256(adjusted.margin) - debit);
        } else if (payment < 0) {
            adjusted.margin = uint128(uint256(adjusted.margin) + uint256(-payment));
        }
    }
}
