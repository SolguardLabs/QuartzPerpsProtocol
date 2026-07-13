// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzEvents } from "../events/QuartzEvents.sol";
import { FundingMath } from "../libraries/FundingMath.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title FundingEngine
/// @notice Stores cumulative funding indexes for each perpetual market.
contract FundingEngine is QuartzEvents {
    using SignedMath for int256;

    QuartzAccessController public immutable accessController;

    mapping(uint256 marketId => QuartzTypes.FundingState state) private _states;

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

    function configureMarket(uint256 marketId, int256 maxRateX18, uint48 minInterval)
        external
        onlyRole(QuartzTypes.GOVERNOR_ROLE)
    {
        if (marketId == 0) revert QuartzErrors.UnknownMarket(marketId);
        if (maxRateX18 <= 0) revert QuartzErrors.InvalidFundingRate();
        if (minInterval == 0) revert QuartzErrors.InvalidAmount();

        QuartzTypes.FundingState storage state = _states[marketId];
        state.enabled = true;
        state.maxRateX18 = maxRateX18;
        state.minInterval = minInterval;
        if (state.lastUpdated == 0) state.lastUpdated = uint48(block.timestamp);

        emit FundingConfigured(marketId, maxRateX18, minInterval);
    }

    function setCurrentRate(uint256 marketId, int256 rateX18)
        external
        onlyRole(QuartzTypes.KEEPER_ROLE)
    {
        QuartzTypes.FundingState storage state = _requireState(marketId);
        state.currentRateX18 = FundingMath.clampRate(rateX18, state.maxRateX18);
    }

    function accrueFunding(uint256 marketId, int256 requestedRateX18)
        external
        onlyRole(QuartzTypes.KEEPER_ROLE)
        returns (int256 nextIndexX18)
    {
        QuartzTypes.FundingState storage state = _requireState(marketId);
        uint256 elapsed = block.timestamp - state.lastUpdated;
        if (elapsed < state.minInterval) {
            revert QuartzErrors.MinIntervalNotElapsed(uint256(state.lastUpdated)
                    + state.minInterval);
        }
        int256 boundedRate = FundingMath.clampRate(requestedRateX18, state.maxRateX18);
        (int256 nextIndex, int256 delta) =
            FundingMath.nextIndex(state.cumulativeFundingIndexX18, boundedRate, elapsed);
        state.cumulativeFundingIndexX18 = nextIndex;
        state.currentRateX18 = boundedRate;
        state.lastUpdated = uint48(block.timestamp);

        emit FundingUpdated(marketId, nextIndex, boundedRate, delta, uint48(block.timestamp));
        return nextIndex;
    }

    function pushFundingDelta(uint256 marketId, int256 deltaX18)
        external
        onlyRole(QuartzTypes.KEEPER_ROLE)
        returns (int256 nextIndexX18)
    {
        QuartzTypes.FundingState storage state = _requireState(marketId);
        if (deltaX18.abs() > state.maxRateX18.abs()) revert QuartzErrors.InvalidFundingRate();
        nextIndexX18 = state.cumulativeFundingIndexX18 + deltaX18;
        state.cumulativeFundingIndexX18 = nextIndexX18;
        state.currentRateX18 = deltaX18;
        state.lastUpdated = uint48(block.timestamp);

        emit FundingUpdated(marketId, nextIndexX18, deltaX18, deltaX18, uint48(block.timestamp));
    }

    function fundingState(uint256 marketId)
        external
        view
        returns (QuartzTypes.FundingState memory)
    {
        return _states[marketId];
    }

    function currentIndex(uint256 marketId) external view returns (int256) {
        return _states[marketId].cumulativeFundingIndexX18;
    }

    function previewPayment(uint256 marketId, int128 sizeX18, int256 lastFundingIndexX18)
        external
        view
        returns (QuartzTypes.FundingPreview memory)
    {
        QuartzTypes.FundingState memory state = _states[marketId];
        return FundingMath.preview(
            sizeX18, state.cumulativeFundingIndexX18, lastFundingIndexX18, state.lastUpdated
        );
    }

    function _requireState(uint256 marketId)
        internal
        view
        returns (QuartzTypes.FundingState storage state)
    {
        state = _states[marketId];
        if (!state.enabled) revert QuartzErrors.UnknownMarket(marketId);
    }
}
