// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title RiskParameterHistory
/// @notice Governance audit trail for market risk parameter snapshots.
contract RiskParameterHistory {
    struct RiskRevision {
        uint256 marketId;
        uint64 revision;
        uint48 timestamp;
        address author;
        bytes32 configHash;
        QuartzTypes.MarketLimits limits;
        bytes32 oracleId;
        bool enabled;
    }

    struct Diff {
        bool enabledChanged;
        bool oracleChanged;
        bool tradeSizeChanged;
        bool marginChanged;
        bool leverageChanged;
        bool maintenanceChanged;
        bool liquidationFeeChanged;
        bool openInterestChanged;
        bool skewChanged;
    }

    QuartzAccessController public immutable accessController;

    mapping(uint256 marketId => RiskRevision[] revisions) private _history;
    mapping(uint256 marketId => bytes32 latestHash) public latestConfigHash;

    event RiskRevisionRecorded(
        uint256 indexed marketId,
        uint64 indexed revision,
        address indexed author,
        bytes32 configHash
    );

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

    function recordConfig(uint256 marketId, QuartzTypes.MarketConfig calldata config)
        external
        onlyGovernor
        returns (uint64 revision)
    {
        if (marketId == 0) revert QuartzErrors.UnknownMarket(marketId);
        bytes32 configHash = hashConfig(config);
        RiskRevision[] storage revisions = _history[marketId];
        if (revisions.length > 0 && revisions[revisions.length - 1].configHash == configHash) {
            return revisions[revisions.length - 1].revision;
        }

        revision = uint64(revisions.length + 1);
        revisions.push(
            RiskRevision({
                marketId: marketId,
                revision: revision,
                timestamp: uint48(block.timestamp),
                author: msg.sender,
                configHash: configHash,
                limits: QuartzTypes.MarketLimits({
                    minTradeSizeX18: config.minTradeSizeX18,
                    minMargin: config.minMargin,
                    maxOpenInterestX18: config.maxOpenInterestX18,
                    maxSkewX18: config.maxSkewX18,
                    maxLeverageX18: config.maxLeverageX18,
                    maintenanceMarginRatioX18: config.maintenanceMarginRatioX18,
                    liquidationFeeRatioX18: config.liquidationFeeRatioX18
                }),
                oracleId: config.oracleId,
                enabled: config.enabled
            })
        );
        latestConfigHash[marketId] = configHash;

        emit RiskRevisionRecorded(marketId, revision, msg.sender, configHash);
    }

    function latest(uint256 marketId) external view returns (RiskRevision memory) {
        RiskRevision[] storage revisions = _history[marketId];
        if (revisions.length == 0) revert QuartzErrors.UnknownMarket(marketId);
        return revisions[revisions.length - 1];
    }

    function revisionAt(uint256 marketId, uint256 index)
        external
        view
        returns (RiskRevision memory)
    {
        return _history[marketId][index];
    }

    function revisionCount(uint256 marketId) external view returns (uint256) {
        return _history[marketId].length;
    }

    function diff(
        QuartzTypes.MarketConfig calldata beforeConfig,
        QuartzTypes.MarketConfig calldata afterConfig
    ) external pure returns (Diff memory result) {
        result.enabledChanged = beforeConfig.enabled != afterConfig.enabled;
        result.oracleChanged = beforeConfig.oracleId != afterConfig.oracleId;
        result.tradeSizeChanged = beforeConfig.minTradeSizeX18 != afterConfig.minTradeSizeX18;
        result.marginChanged = beforeConfig.minMargin != afterConfig.minMargin;
        result.leverageChanged = beforeConfig.maxLeverageX18 != afterConfig.maxLeverageX18;
        result.maintenanceChanged =
            beforeConfig.maintenanceMarginRatioX18 != afterConfig.maintenanceMarginRatioX18;
        result.liquidationFeeChanged =
            beforeConfig.liquidationFeeRatioX18 != afterConfig.liquidationFeeRatioX18;
        result.openInterestChanged =
            beforeConfig.maxOpenInterestX18 != afterConfig.maxOpenInterestX18;
        result.skewChanged = beforeConfig.maxSkewX18 != afterConfig.maxSkewX18;
    }

    function hashConfig(QuartzTypes.MarketConfig calldata config) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                config.enabled,
                config.oracleId,
                keccak256(bytes(config.symbol)),
                config.maxOracleAge,
                config.minTradeSizeX18,
                config.minMargin,
                config.maxOpenInterestX18,
                config.maxSkewX18,
                config.maxLeverageX18,
                config.maintenanceMarginRatioX18,
                config.liquidationFeeRatioX18,
                config.fundingVelocityX18
            )
        );
    }
}
