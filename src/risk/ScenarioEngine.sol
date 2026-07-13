// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FundingEngine } from "../core/FundingEngine.sol";
import { PositionBook } from "../core/PositionBook.sol";
import { AccountMath } from "../libraries/AccountMath.sol";
import { FundingMath } from "../libraries/FundingMath.sol";
import { PositionMath } from "../libraries/PositionMath.sol";
import { OracleRouter } from "../oracle/OracleRouter.sol";
import { RiskEngine } from "./RiskEngine.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title ScenarioEngine
/// @notice View-only simulations for frontends, keepers, and risk operators.
contract ScenarioEngine {
    FundingEngine public immutable fundingEngine;
    PositionBook public immutable positionBook;
    OracleRouter public immutable oracleRouter;
    RiskEngine public immutable riskEngine;

    struct TradeScenario {
        QuartzTypes.Position beforePosition;
        QuartzTypes.Position afterPosition;
        QuartzTypes.RiskSnapshot beforeRisk;
        QuartzTypes.RiskSnapshot afterRisk;
        QuartzTypes.FundingPreview fundingPreview;
        int256 realizedPnl;
        uint256 fundingDeficit;
        bool increasesRisk;
    }

    struct LiquidationScenario {
        QuartzTypes.Position position;
        QuartzTypes.RiskSnapshot risk;
        int256 closePnl;
        uint256 estimatedReward;
        uint256 estimatedInsuranceCredit;
        uint256 estimatedBadDebt;
        bool executable;
    }

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

    function previewIncrease(
        address trader,
        uint256 marketId,
        int128 sizeDelta,
        uint256 marginAmount
    ) external view returns (TradeScenario memory scenario) {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        scenario = _baseScenario(marketId, position, config, price.priceX18);

        AccountMath.FundingApplication memory funding =
            AccountMath.applyFunding(position, scenario.fundingPreview.payment);
        scenario.afterPosition = funding.positionAfter;
        scenario.fundingDeficit = funding.deficit;
        scenario.afterPosition.margin =
            _toUint128(uint256(scenario.afterPosition.margin) + marginAmount);
        scenario.afterPosition.size =
            int128(int256(scenario.afterPosition.size) + int256(sizeDelta));
        scenario.afterPosition.entryPriceX18 = _toUint128(
            PositionMath.nextEntryPrice(
                position.size, position.entryPriceX18, sizeDelta, price.priceX18
            )
        );
        scenario.afterRisk =
            riskEngine.previewRisk(marketId, scenario.afterPosition, price.priceX18);
        scenario.increasesRisk =
            scenario.afterRisk.healthFactorX18 < scenario.beforeRisk.healthFactorX18;
    }

    function previewDecrease(address trader, uint256 marketId, uint128 sizeAmountX18)
        external
        view
        returns (TradeScenario memory scenario)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        scenario = _baseScenario(marketId, position, config, price.priceX18);

        AccountMath.FundingApplication memory funding =
            AccountMath.applyFunding(position, scenario.fundingPreview.payment);
        scenario.afterPosition = funding.positionAfter;
        scenario.fundingDeficit = funding.deficit;
        scenario.realizedPnl = PositionMath.realizedPnlForReduction(
            position.size, position.entryPriceX18, price.priceX18, sizeAmountX18
        );
        (scenario.afterPosition, scenario.fundingDeficit) =
            AccountMath.applyRealizedPnl(scenario.afterPosition, scenario.realizedPnl);
        scenario.afterPosition.size = PositionMath.reduceSize(position.size, sizeAmountX18);
        if (scenario.afterPosition.size == 0) scenario.afterPosition.entryPriceX18 = 0;
        scenario.afterRisk =
            riskEngine.previewRisk(marketId, scenario.afterPosition, price.priceX18);
        scenario.increasesRisk =
            scenario.afterRisk.healthFactorX18 < scenario.beforeRisk.healthFactorX18;
    }

    function previewWithdrawal(address trader, uint256 marketId, uint256 amount)
        external
        view
        returns (AccountMath.WithdrawalProjection memory)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        return AccountMath.projectWithdrawal(marketId, position, config, price.priceX18, amount);
    }

    function previewLiquidation(address trader, uint256 marketId)
        external
        view
        returns (LiquidationScenario memory scenario)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        scenario.position = positionBook.position(trader, marketId);
        scenario.risk = riskEngine.previewRisk(marketId, scenario.position, price.priceX18);
        scenario.closePnl = PositionMath.unrealizedPnl(
            scenario.position.size, scenario.position.entryPriceX18, price.priceX18
        );
        (uint256 marginAfterClose, uint256 badDebt) =
            PositionMath.marginAfterPnl(scenario.position.margin, scenario.closePnl);
        scenario.estimatedReward = scenario.risk.liquidationFee;
        if (scenario.estimatedReward > marginAfterClose) {
            scenario.estimatedReward = marginAfterClose;
        }
        scenario.estimatedInsuranceCredit = marginAfterClose - scenario.estimatedReward;
        scenario.estimatedBadDebt = badDebt;
        scenario.executable = scenario.risk.liquidatable;
    }

    function _baseScenario(
        uint256 marketId,
        QuartzTypes.Position memory position,
        QuartzTypes.MarketConfig memory config,
        uint256 priceX18
    ) internal view returns (TradeScenario memory scenario) {
        QuartzTypes.FundingState memory funding = fundingEngine.fundingState(marketId);
        scenario.beforePosition = position;
        scenario.afterPosition = position;
        scenario.beforeRisk = riskEngine.previewRisk(marketId, position, priceX18);
        scenario.afterRisk = scenario.beforeRisk;
        scenario.fundingPreview = FundingMath.preview(
            position.size,
            funding.cumulativeFundingIndexX18,
            position.lastFundingIndexX18,
            funding.lastUpdated
        );
        config;
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert();
        return uint128(value);
    }
}
