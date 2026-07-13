// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { PositionMath } from "../libraries/PositionMath.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title PositionBook
/// @notice Canonical storage for isolated margin positions and market exposure.
contract PositionBook {
    QuartzAccessController public immutable accessController;

    mapping(address trader => mapping(uint256 marketId => QuartzTypes.Position position)) private
        _positions;
    mapping(uint256 marketId => QuartzTypes.MarketExposure exposure) private _exposures;

    constructor(address accessController_) {
        if (accessController_ == address(0)) revert QuartzErrors.ZeroAddress();
        accessController = QuartzAccessController(accessController_);
    }

    modifier onlyManager() {
        if (!accessController.hasRole(QuartzTypes.MANAGER_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.MANAGER_ROLE, msg.sender);
        }
        _;
    }

    function position(address trader, uint256 marketId)
        external
        view
        returns (QuartzTypes.Position memory)
    {
        return _positions[trader][marketId];
    }

    function exposure(uint256 marketId) external view returns (QuartzTypes.MarketExposure memory) {
        return _exposures[marketId];
    }

    function storePosition(
        address trader,
        uint256 marketId,
        QuartzTypes.Position calldata nextPosition
    ) external onlyManager returns (QuartzTypes.Position memory previous) {
        if (trader == address(0)) revert QuartzErrors.ZeroAddress();
        previous = _positions[trader][marketId];
        _updateExposure(marketId, previous.size, nextPosition.size);
        _positions[trader][marketId] = nextPosition;
    }

    function deletePosition(address trader, uint256 marketId)
        external
        onlyManager
        returns (QuartzTypes.Position memory previous)
    {
        previous = _positions[trader][marketId];
        _updateExposure(marketId, previous.size, 0);
        delete _positions[trader][marketId];
    }

    function setMargin(address trader, uint256 marketId, uint128 margin)
        external
        onlyManager
        returns (QuartzTypes.Position memory position_)
    {
        position_ = _positions[trader][marketId];
        if (!position_.exists) revert QuartzErrors.PositionNotFound(trader, marketId);
        position_.margin = margin;
        position_.lastUpdated = uint48(block.timestamp);
        _positions[trader][marketId] = position_;
    }

    function setFundingIndex(address trader, uint256 marketId, int256 fundingIndexX18)
        external
        onlyManager
        returns (QuartzTypes.Position memory position_)
    {
        position_ = _positions[trader][marketId];
        if (!position_.exists) revert QuartzErrors.PositionNotFound(trader, marketId);
        position_.lastFundingIndexX18 = fundingIndexX18;
        position_.lastUpdated = uint48(block.timestamp);
        _positions[trader][marketId] = position_;
    }

    function projectedExposure(uint256 marketId, int128 oldSize, int128 nextSize)
        external
        view
        returns (QuartzTypes.MarketExposure memory next)
    {
        next = _exposures[marketId];
        _removeMemory(next, oldSize);
        _addMemory(next, nextSize);
    }

    function _updateExposure(uint256 marketId, int128 oldSize, int128 nextSize) internal {
        if (oldSize == nextSize) return;
        QuartzTypes.MarketExposure storage exposure_ = _exposures[marketId];
        _remove(exposure_, oldSize);
        _add(exposure_, nextSize);
        exposure_.lastUpdated = uint48(block.timestamp);
    }

    function _remove(QuartzTypes.MarketExposure storage exposure_, int128 size) internal {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure_.longOpenInterestX18 -= amount;
            exposure_.skewX18 -= size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure_.shortOpenInterestX18 -= amount;
            exposure_.skewX18 -= size;
        }
    }

    function _removeMemory(QuartzTypes.MarketExposure memory exposure_, int128 size) internal pure {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure_.longOpenInterestX18 -= amount;
            exposure_.skewX18 -= size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure_.shortOpenInterestX18 -= amount;
            exposure_.skewX18 -= size;
        }
    }

    function _add(QuartzTypes.MarketExposure storage exposure_, int128 size) internal {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure_.longOpenInterestX18 += amount;
            exposure_.skewX18 += size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure_.shortOpenInterestX18 += amount;
            exposure_.skewX18 += size;
        }
    }

    function _addMemory(QuartzTypes.MarketExposure memory exposure_, int128 size) internal pure {
        if (size > 0) {
            uint128 amount = uint128(uint256(int256(size)));
            exposure_.longOpenInterestX18 += amount;
            exposure_.skewX18 += size;
        } else if (size < 0) {
            uint128 amount = uint128(uint256(-int256(size)));
            exposure_.shortOpenInterestX18 += amount;
            exposure_.skewX18 += size;
        }
    }

    function notional(address trader, uint256 marketId, uint256 priceX18)
        external
        view
        returns (uint256)
    {
        QuartzTypes.Position memory stored = _positions[trader][marketId];
        return PositionMath.notional(stored.size, priceX18);
    }
}
