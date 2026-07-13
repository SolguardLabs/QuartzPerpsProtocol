// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title QuartzTypes
/// @notice Shared domain types for the Quartz isolated-margin perpetual protocol.
library QuartzTypes {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;

    bytes32 internal constant GOVERNOR_ROLE = keccak256("QUARTZ_GOVERNOR");
    bytes32 internal constant KEEPER_ROLE = keccak256("QUARTZ_KEEPER");
    bytes32 internal constant MANAGER_ROLE = keccak256("QUARTZ_MANAGER");
    bytes32 internal constant LIQUIDATOR_ROLE = keccak256("QUARTZ_LIQUIDATOR");
    bytes32 internal constant REPORTER_ROLE = keccak256("QUARTZ_REPORTER");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("QUARTZ_GUARDIAN");

    enum PositionStatus {
        None,
        Open,
        Closed,
        Liquidated
    }

    enum MarginMode {
        Isolated,
        Reserved
    }

    struct MarketConfig {
        bool enabled;
        bytes32 oracleId;
        string symbol;
        uint48 maxOracleAge;
        uint128 minTradeSizeX18;
        uint128 minMargin;
        uint128 maxOpenInterestX18;
        uint128 maxSkewX18;
        uint64 maxLeverageX18;
        uint64 maintenanceMarginRatioX18;
        uint64 liquidationFeeRatioX18;
        uint64 fundingVelocityX18;
    }

    struct MarketLimits {
        uint128 minTradeSizeX18;
        uint128 minMargin;
        uint128 maxOpenInterestX18;
        uint128 maxSkewX18;
        uint64 maxLeverageX18;
        uint64 maintenanceMarginRatioX18;
        uint64 liquidationFeeRatioX18;
    }

    struct PriceFeed {
        bool enabled;
        uint256 priceX18;
        uint256 minPriceX18;
        uint256 maxPriceX18;
        uint48 updatedAt;
        uint48 maxAge;
    }

    struct PriceData {
        bytes32 oracleId;
        uint256 priceX18;
        uint48 updatedAt;
        uint48 maxAge;
    }

    struct FundingState {
        bool enabled;
        int256 cumulativeFundingIndexX18;
        int256 currentRateX18;
        int256 maxRateX18;
        uint48 lastUpdated;
        uint48 minInterval;
    }

    struct FundingPreview {
        int256 currentIndexX18;
        int256 lastIndexX18;
        int256 indexDeltaX18;
        int256 payment;
        uint48 lastUpdated;
    }

    struct Position {
        bool exists;
        PositionStatus status;
        MarginMode marginMode;
        int128 size;
        uint128 margin;
        uint128 entryPriceX18;
        int256 lastFundingIndexX18;
        int256 realizedPnl;
        uint48 openedAt;
        uint48 lastUpdated;
    }

    struct PositionDelta {
        int128 sizeDelta;
        uint128 marginDelta;
        uint256 executionPriceX18;
        int256 realizedPnl;
        int256 fundingPayment;
    }

    struct MarketExposure {
        uint128 longOpenInterestX18;
        uint128 shortOpenInterestX18;
        int128 skewX18;
        uint48 lastUpdated;
    }

    struct RiskSnapshot {
        uint256 marketId;
        uint256 priceX18;
        uint256 notional;
        uint256 initialMargin;
        uint256 maintenanceMargin;
        uint256 liquidationFee;
        int256 unrealizedPnl;
        int256 equity;
        uint256 margin;
        uint256 healthFactorX18;
        bool liquidatable;
        bool initialMarginSatisfied;
    }

    struct AccountSnapshot {
        address trader;
        uint256 marketId;
        Position position;
        PriceData price;
        FundingPreview funding;
        RiskSnapshot riskBeforeFunding;
        RiskSnapshot riskAfterFunding;
    }

    struct LiquidationResult {
        address trader;
        address liquidator;
        uint256 marketId;
        uint256 priceX18;
        int256 closePnl;
        uint256 reward;
        uint256 insuranceCredit;
        uint256 badDebt;
    }

    struct OpenPositionParams {
        uint256 marketId;
        int128 sizeDelta;
        uint256 marginAmount;
        uint256 acceptablePriceX18;
    }

    struct IncreasePositionParams {
        uint256 marketId;
        int128 sizeDelta;
        uint256 marginAmount;
        uint256 acceptablePriceX18;
    }

    struct DecreasePositionParams {
        uint256 marketId;
        uint128 sizeAmountX18;
        uint256 acceptablePriceX18;
        address receiver;
    }

    struct WithdrawalRequest {
        uint256 marketId;
        uint256 amount;
        address receiver;
    }

    struct DeploymentConfig {
        address collateralToken;
        address accessController;
        address collateralVault;
        address oracleRouter;
        address fundingEngine;
        address riskEngine;
        address positionBook;
        address insuranceFund;
    }
}
