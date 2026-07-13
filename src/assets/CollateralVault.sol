// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title CollateralVault
/// @notice Holds settlement collateral and releases it under manager-controlled workflows.
contract CollateralVault {
    using SafeTransferLib for address;

    QuartzAccessController public immutable accessController;
    address public immutable collateralToken;

    uint256 public totalCollected;
    uint256 public totalReleased;

    constructor(address accessController_, address collateralToken_) {
        if (accessController_ == address(0) || collateralToken_ == address(0)) {
            revert QuartzErrors.ZeroAddress();
        }
        accessController = QuartzAccessController(accessController_);
        collateralToken = collateralToken_;
    }

    modifier onlyManager() {
        if (!accessController.hasRole(QuartzTypes.MANAGER_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.MANAGER_ROLE, msg.sender);
        }
        _;
    }

    function collect(address from, uint256 amount) external onlyManager {
        if (from == address(0)) revert QuartzErrors.ZeroAddress();
        if (amount == 0) revert QuartzErrors.InvalidAmount();
        totalCollected += amount;
        collateralToken.safeTransferFrom(from, address(this), amount);
    }

    function release(address to, uint256 amount) external onlyManager {
        if (to == address(0)) revert QuartzErrors.ZeroAddress();
        if (amount == 0) return;
        totalReleased += amount;
        collateralToken.safeTransfer(to, amount);
    }

    function balance() external view returns (uint256) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    function netFlow() external view returns (int256) {
        if (totalCollected >= totalReleased) return int256(totalCollected - totalReleased);
        return -int256(totalReleased - totalCollected);
    }
}
