// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title QuartzEvents
/// @notice Event surface for accounts, risk, funding, and governance changes.
contract QuartzEvents {
    event MarketConfigured(
        uint256 indexed marketId,
        bytes32 indexed oracleId,
        string symbol,
        uint256 maxLeverageX18,
        uint256 maintenanceMarginRatioX18
    );
    event PriceFeedConfigured(
        bytes32 indexed oracleId, uint256 minPriceX18, uint256 maxPriceX18, uint48 maxAge
    );
    event PriceReported(bytes32 indexed oracleId, uint256 priceX18, uint48 updatedAt);
    event FundingConfigured(uint256 indexed marketId, int256 maxRateX18, uint48 minInterval);
    event FundingUpdated(
        uint256 indexed marketId,
        int256 cumulativeFundingIndexX18,
        int256 rateX18,
        int256 deltaX18,
        uint48 updatedAt
    );
    event MarginDeposited(
        address indexed trader, uint256 indexed marketId, uint256 amount, uint256 newMargin
    );
    event MarginWithdrawn(
        address indexed trader,
        uint256 indexed marketId,
        address indexed receiver,
        uint256 amount,
        uint256 newMargin
    );
    event PositionOpened(
        address indexed trader,
        uint256 indexed marketId,
        int128 size,
        uint256 margin,
        uint256 entryPriceX18
    );
    event PositionIncreased(
        address indexed trader,
        uint256 indexed marketId,
        int128 sizeDelta,
        int128 newSize,
        uint256 margin,
        uint256 entryPriceX18
    );
    event PositionDecreased(
        address indexed trader,
        uint256 indexed marketId,
        uint128 reducedSizeX18,
        int128 newSize,
        int256 realizedPnl,
        uint256 margin
    );
    event FundingSettled(
        address indexed trader,
        uint256 indexed marketId,
        int256 fundingPayment,
        int256 fundingIndexX18,
        uint256 marginAfter
    );
    event PositionLiquidated(
        address indexed trader,
        address indexed liquidator,
        uint256 indexed marketId,
        int256 closePnl,
        uint256 reward,
        uint256 insuranceCredit,
        uint256 badDebt
    );
    event InsuranceAccountingUpdated(uint256 credited, uint256 badDebt, uint256 outstanding);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event PauseStatusUpdated(bool paused);
}
