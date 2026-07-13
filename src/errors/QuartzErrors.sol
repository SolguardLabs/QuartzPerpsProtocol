// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title QuartzErrors
/// @notice Centralized custom errors used across Quartz contracts.
library QuartzErrors {
    error ZeroAddress();
    error Unauthorized(bytes32 role, address account);
    error ProtocolPaused();
    error MarketDisabled(uint256 marketId);
    error MarketAlreadyConfigured(uint256 marketId);
    error UnknownMarket(uint256 marketId);
    error UnknownOracle(bytes32 oracleId);
    error StalePrice(bytes32 oracleId, uint256 updatedAt, uint256 maxAge);
    error PriceOutOfBounds(bytes32 oracleId, uint256 price);
    error InvalidAmount();
    error InvalidSize();
    error InvalidMargin();
    error InvalidPrice();
    error InvalidReceiver();
    error InvalidFundingRate();
    error MinIntervalNotElapsed(uint256 readyAt);
    error PositionExists(address trader, uint256 marketId);
    error PositionNotFound(address trader, uint256 marketId);
    error PositionClosed(address trader, uint256 marketId);
    error DirectionMismatch();
    error ReduceExceedsPosition(uint256 requested, uint256 available);
    error Slippage(uint256 observedPrice, uint256 acceptablePrice);
    error InsufficientMargin(uint256 available, uint256 required);
    error InitialMarginRequirement(int256 equity, uint256 requirement);
    error MaintenanceMarginSatisfied(int256 equity, uint256 requirement);
    error OpenInterestLimit(uint256 nextOpenInterest, uint256 limit);
    error SkewLimit(int256 nextSkew, uint256 limit);
    error TransferFailed();
    error Reentrancy();
    error ArrayLengthMismatch();
    error Overflow();
}
