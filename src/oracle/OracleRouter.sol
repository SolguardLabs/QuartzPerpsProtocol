// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzEvents } from "../events/QuartzEvents.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title OracleRouter
/// @notice Permissioned price feed router with freshness and bound checks.
contract OracleRouter is QuartzEvents {
    QuartzAccessController public immutable accessController;

    mapping(bytes32 oracleId => QuartzTypes.PriceFeed feed) private _feeds;

    constructor(address accessController_) {
        if (accessController_ == address(0)) revert QuartzErrors.ZeroAddress();
        accessController = QuartzAccessController(accessController_);
    }

    modifier onlyRole(bytes32 role) {
        if (!accessController.hasRole(role, msg.sender)) {
            revert QuartzErrors.Unauthorized(role, msg.sender);
        }
        _;
    }

    function configureFeed(
        bytes32 oracleId,
        uint256 minPriceX18,
        uint256 maxPriceX18,
        uint48 maxAge
    ) external onlyRole(QuartzTypes.GOVERNOR_ROLE) {
        if (oracleId == bytes32(0)) revert QuartzErrors.UnknownOracle(oracleId);
        if (minPriceX18 == 0 || maxPriceX18 <= minPriceX18) revert QuartzErrors.InvalidPrice();
        if (maxAge == 0) revert QuartzErrors.InvalidAmount();

        QuartzTypes.PriceFeed storage storedFeed = _feeds[oracleId];
        storedFeed.enabled = true;
        storedFeed.minPriceX18 = minPriceX18;
        storedFeed.maxPriceX18 = maxPriceX18;
        storedFeed.maxAge = maxAge;

        emit PriceFeedConfigured(oracleId, minPriceX18, maxPriceX18, maxAge);
    }

    function reportPrice(bytes32 oracleId, uint256 priceX18)
        external
        onlyRole(QuartzTypes.REPORTER_ROLE)
    {
        QuartzTypes.PriceFeed storage storedFeed = _feeds[oracleId];
        if (!storedFeed.enabled) revert QuartzErrors.UnknownOracle(oracleId);
        if (priceX18 < storedFeed.minPriceX18 || priceX18 > storedFeed.maxPriceX18) {
            revert QuartzErrors.PriceOutOfBounds(oracleId, priceX18);
        }
        storedFeed.priceX18 = priceX18;
        storedFeed.updatedAt = uint48(block.timestamp);

        emit PriceReported(oracleId, priceX18, uint48(block.timestamp));
    }

    function getPrice(bytes32 oracleId) external view returns (QuartzTypes.PriceData memory data) {
        QuartzTypes.PriceFeed memory storedFeed = _feeds[oracleId];
        if (!storedFeed.enabled || storedFeed.priceX18 == 0) {
            revert QuartzErrors.UnknownOracle(oracleId);
        }
        if (block.timestamp > uint256(storedFeed.updatedAt) + storedFeed.maxAge) {
            revert QuartzErrors.StalePrice(oracleId, storedFeed.updatedAt, storedFeed.maxAge);
        }
        data = QuartzTypes.PriceData({
            oracleId: oracleId,
            priceX18: storedFeed.priceX18,
            updatedAt: storedFeed.updatedAt,
            maxAge: storedFeed.maxAge
        });
    }

    function feed(bytes32 oracleId) external view returns (QuartzTypes.PriceFeed memory) {
        return _feeds[oracleId];
    }
}
