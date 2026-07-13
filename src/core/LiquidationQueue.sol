// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { PositionBook } from "./PositionBook.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { OracleRouter } from "../oracle/OracleRouter.sol";
import { RiskEngine } from "../risk/RiskEngine.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title LiquidationQueue
/// @notice Keeper-facing registry for accounts observed below maintenance margin.
contract LiquidationQueue {
    struct Candidate {
        address trader;
        uint256 marketId;
        uint256 observedHealthFactorX18;
        uint48 queuedAt;
        uint48 lastRefresh;
        bool active;
    }

    QuartzAccessController public immutable accessController;
    RiskEngine public immutable riskEngine;
    OracleRouter public immutable oracleRouter;
    PositionBook public immutable positionBook;

    mapping(bytes32 id => Candidate candidate) private _candidates;
    bytes32[] private _candidateIds;

    event CandidateQueued(
        bytes32 indexed id,
        address indexed trader,
        uint256 indexed marketId,
        uint256 healthFactorX18
    );
    event CandidateRefreshed(bytes32 indexed id, uint256 healthFactorX18, bool stillActive);
    event CandidateCleared(bytes32 indexed id, address indexed sender);

    constructor(
        address accessController_,
        address riskEngine_,
        address oracleRouter_,
        address positionBook_
    ) {
        if (
            accessController_ == address(0) || riskEngine_ == address(0)
                || oracleRouter_ == address(0) || positionBook_ == address(0)
        ) {
            revert QuartzErrors.ZeroAddress();
        }
        accessController = QuartzAccessController(accessController_);
        riskEngine = RiskEngine(riskEngine_);
        oracleRouter = OracleRouter(oracleRouter_);
        positionBook = PositionBook(positionBook_);
    }

    modifier onlyKeeper() {
        if (!accessController.hasRole(QuartzTypes.KEEPER_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.KEEPER_ROLE, msg.sender);
        }
        _;
    }

    modifier onlyManager() {
        if (!accessController.hasRole(QuartzTypes.MANAGER_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.MANAGER_ROLE, msg.sender);
        }
        _;
    }

    function queue(address trader, uint256 marketId) external onlyKeeper returns (bytes32 id) {
        if (trader == address(0)) revert QuartzErrors.ZeroAddress();
        QuartzTypes.RiskSnapshot memory snapshot = _snapshot(trader, marketId);
        if (!snapshot.liquidatable) {
            revert QuartzErrors.MaintenanceMarginSatisfied(
                snapshot.equity, snapshot.maintenanceMargin
            );
        }

        id = candidateId(trader, marketId);
        Candidate storage candidate = _candidates[id];
        if (!candidate.active && candidate.queuedAt == 0) _candidateIds.push(id);

        candidate.trader = trader;
        candidate.marketId = marketId;
        candidate.observedHealthFactorX18 = snapshot.healthFactorX18;
        candidate.queuedAt = candidate.queuedAt == 0 ? uint48(block.timestamp) : candidate.queuedAt;
        candidate.lastRefresh = uint48(block.timestamp);
        candidate.active = true;

        emit CandidateQueued(id, trader, marketId, snapshot.healthFactorX18);
    }

    function refresh(bytes32 id) external onlyKeeper returns (bool active) {
        Candidate storage candidate = _candidates[id];
        if (candidate.trader == address(0)) revert QuartzErrors.PositionNotFound(address(0), 0);
        QuartzTypes.RiskSnapshot memory snapshot = _snapshot(candidate.trader, candidate.marketId);
        candidate.observedHealthFactorX18 = snapshot.healthFactorX18;
        candidate.lastRefresh = uint48(block.timestamp);
        candidate.active = snapshot.liquidatable;
        emit CandidateRefreshed(id, snapshot.healthFactorX18, candidate.active);
        return candidate.active;
    }

    function clear(bytes32 id) external onlyManager {
        Candidate storage candidate = _candidates[id];
        if (!candidate.active) return;
        candidate.active = false;
        candidate.lastRefresh = uint48(block.timestamp);
        emit CandidateCleared(id, msg.sender);
    }

    function candidate(bytes32 id) external view returns (Candidate memory) {
        return _candidates[id];
    }

    function candidateAt(uint256 index) external view returns (Candidate memory) {
        return _candidates[_candidateIds[index]];
    }

    function candidateCount() external view returns (uint256) {
        return _candidateIds.length;
    }

    function candidateId(address trader, uint256 marketId) public pure returns (bytes32) {
        return keccak256(abi.encode(trader, marketId));
    }

    function _snapshot(address trader, uint256 marketId)
        internal
        view
        returns (QuartzTypes.RiskSnapshot memory)
    {
        QuartzTypes.MarketConfig memory config = riskEngine.market(marketId);
        QuartzTypes.PriceData memory price = oracleRouter.getPrice(config.oracleId);
        QuartzTypes.Position memory position = positionBook.position(trader, marketId);
        if (!position.exists || position.size == 0) {
            revert QuartzErrors.PositionNotFound(trader, marketId);
        }
        return riskEngine.previewRisk(marketId, position, price.priceX18);
    }
}
