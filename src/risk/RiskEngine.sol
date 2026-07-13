// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzEvents } from "../events/QuartzEvents.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { MarginMath } from "../libraries/MarginMath.sol";
import { PositionMath } from "../libraries/PositionMath.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title RiskEngine
/// @notice Market parameter registry and margin validation engine.
contract RiskEngine is QuartzEvents {
    using FixedPointMath for uint256;

    QuartzAccessController public immutable accessController;

    mapping(uint256 marketId => QuartzTypes.MarketConfig config) private _markets;
    uint256[] private _marketIds;

    constructor(address accessController_) {
        if (accessController_ == address(0)) revert QuartzErrors.ZeroAddress();
        accessController = QuartzAccessController(accessController_);
    }

    modifier onlyGovernor() {
        if (!accessController.hasRole(QuartzTypes.GOVERNOR_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.GOVERNOR_ROLE, msg.sender);
        }
        _;
    }

    function configureMarket(uint256 marketId, QuartzTypes.MarketConfig calldata config)
        external
        onlyGovernor
    {
        _validateConfig(marketId, config);
        if (!_markets[marketId].enabled) _marketIds.push(marketId);
        _markets[marketId] = config;
        emit MarketConfigured(
            marketId,
            config.oracleId,
            config.symbol,
            config.maxLeverageX18,
            config.maintenanceMarginRatioX18
        );
    }

    function setMarketEnabled(uint256 marketId, bool enabled) external onlyGovernor {
        QuartzTypes.MarketConfig storage config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        config.enabled = enabled;
    }

    function market(uint256 marketId) external view returns (QuartzTypes.MarketConfig memory) {
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        return config;
    }

    function marketIds() external view returns (uint256[] memory) {
        return _marketIds;
    }

    function requireEnabledMarket(uint256 marketId)
        external
        view
        returns (QuartzTypes.MarketConfig memory config)
    {
        config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        if (!config.enabled) revert QuartzErrors.MarketDisabled(marketId);
    }

    function buildRiskSnapshot(
        uint256 marketId,
        QuartzTypes.Position calldata position,
        uint256 priceX18
    ) external view returns (QuartzTypes.RiskSnapshot memory) {
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        return MarginMath.buildRiskSnapshot(marketId, position, config, priceX18);
    }

    function previewRisk(uint256 marketId, QuartzTypes.Position memory position, uint256 priceX18)
        public
        view
        returns (QuartzTypes.RiskSnapshot memory)
    {
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        return MarginMath.buildRiskSnapshot(marketId, position, config, priceX18);
    }

    function validateInitialMargin(
        uint256 marketId,
        QuartzTypes.Position memory position,
        uint256 priceX18
    ) external view returns (QuartzTypes.RiskSnapshot memory snapshot) {
        snapshot = previewRisk(marketId, position, priceX18);
        if (!snapshot.initialMarginSatisfied) {
            revert QuartzErrors.InitialMarginRequirement(snapshot.equity, snapshot.initialMargin);
        }
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (position.margin < config.minMargin) {
            revert QuartzErrors.InsufficientMargin(position.margin, config.minMargin);
        }
    }

    function validateWithdrawal(
        uint256 marketId,
        QuartzTypes.Position memory position,
        uint256 priceX18
    ) external view returns (QuartzTypes.RiskSnapshot memory snapshot) {
        snapshot = previewRisk(marketId, position, priceX18);
        if (position.size != 0 && !snapshot.initialMarginSatisfied) {
            revert QuartzErrors.InitialMarginRequirement(snapshot.equity, snapshot.initialMargin);
        }
        if (position.size != 0 && position.margin < _markets[marketId].minMargin) {
            revert QuartzErrors.InsufficientMargin(position.margin, _markets[marketId].minMargin);
        }
    }

    function validateExposure(
        uint256 marketId,
        QuartzTypes.MarketExposure memory exposure,
        int128 oldSize,
        int128 nextSize
    ) external view {
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        (uint256 nextLong, uint256 nextShort, int256 nextSkew) =
            _projectExposure(exposure, oldSize, nextSize);

        uint256 nextOpenInterest = nextLong + nextShort;
        if (nextOpenInterest > config.maxOpenInterestX18) {
            revert QuartzErrors.OpenInterestLimit(nextOpenInterest, config.maxOpenInterestX18);
        }
        if (SignedMath.abs(nextSkew) > config.maxSkewX18) {
            revert QuartzErrors.SkewLimit(nextSkew, config.maxSkewX18);
        }
    }

    function liquidationFee(uint256 marketId, int128 sizeX18, uint256 priceX18)
        external
        view
        returns (uint256)
    {
        QuartzTypes.MarketConfig memory config = _markets[marketId];
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownMarket(marketId);
        uint256 positionNotional = PositionMath.notional(sizeX18, priceX18);
        return MarginMath.liquidationFee(positionNotional, config.liquidationFeeRatioX18);
    }

    function _validateConfig(uint256 marketId, QuartzTypes.MarketConfig calldata config)
        internal
        pure
    {
        if (marketId == 0) revert QuartzErrors.UnknownMarket(marketId);
        if (config.oracleId == bytes32(0)) revert QuartzErrors.UnknownOracle(config.oracleId);
        if (bytes(config.symbol).length == 0) revert QuartzErrors.InvalidAmount();
        if (config.maxOracleAge == 0) revert QuartzErrors.InvalidAmount();
        if (config.minTradeSizeX18 == 0) revert QuartzErrors.InvalidSize();
        if (config.minMargin == 0) revert QuartzErrors.InvalidMargin();
        if (config.maxLeverageX18 <= QuartzTypes.WAD) revert QuartzErrors.InvalidMargin();
        if (config.maintenanceMarginRatioX18 == 0) revert QuartzErrors.InvalidMargin();
        if (config.maintenanceMarginRatioX18 >= QuartzTypes.WAD) {
            revert QuartzErrors.InvalidMargin();
        }
        if (config.liquidationFeeRatioX18 > config.maintenanceMarginRatioX18) {
            revert QuartzErrors.InvalidMargin();
        }
        if (config.maxOpenInterestX18 == 0 || config.maxSkewX18 == 0) {
            revert QuartzErrors.InvalidSize();
        }
    }

    function _projectExposure(
        QuartzTypes.MarketExposure memory exposure,
        int128 oldSize,
        int128 nextSize
    ) internal pure returns (uint256 nextLong, uint256 nextShort, int256 nextSkew) {
        nextLong = exposure.longOpenInterestX18;
        nextShort = exposure.shortOpenInterestX18;
        nextSkew = exposure.skewX18;
        (nextLong, nextShort, nextSkew) = _removeExposure(nextLong, nextShort, nextSkew, oldSize);
        (nextLong, nextShort, nextSkew) = _applyExposure(nextLong, nextShort, nextSkew, nextSize);
    }

    function _removeExposure(uint256 longOi, uint256 shortOi, int256 skew, int128 size)
        internal
        pure
        returns (uint256 nextLong, uint256 nextShort, int256 nextSkew)
    {
        nextLong = longOi;
        nextShort = shortOi;
        nextSkew = skew;
        if (size > 0) {
            nextLong -= uint256(int256(size));
            nextSkew -= int256(size);
        } else if (size < 0) {
            nextShort -= uint256(-int256(size));
            nextSkew -= int256(size);
        }
    }

    function _applyExposure(uint256 longOi, uint256 shortOi, int256 skew, int128 size)
        internal
        pure
        returns (uint256 nextLong, uint256 nextShort, int256 nextSkew)
    {
        nextLong = longOi;
        nextShort = shortOi;
        nextSkew = skew;
        if (size > 0) {
            nextLong += uint256(int256(size));
            nextSkew += int256(size);
        } else if (size < 0) {
            nextShort += uint256(-int256(size));
            nextSkew += int256(size);
        }
    }
}
