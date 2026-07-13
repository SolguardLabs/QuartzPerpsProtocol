// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzEvents } from "../events/QuartzEvents.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title InsuranceFund
/// @notice Tracks protocol reserves, liquidation credits, and unresolved deficits.
contract InsuranceFund is QuartzEvents {
    using SafeTransferLib for address;

    QuartzAccessController public immutable accessController;
    address public immutable collateralToken;

    uint256 public creditedReserves;
    uint256 public reportedBadDebt;
    uint256 public coveredBadDebt;
    uint256 public feeIncome;

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

    modifier onlyGovernor() {
        if (!accessController.hasRole(QuartzTypes.GOVERNOR_ROLE, msg.sender)) {
            revert QuartzErrors.Unauthorized(QuartzTypes.GOVERNOR_ROLE, msg.sender);
        }
        _;
    }

    function recordCredit(uint256 amount) external onlyManager {
        if (amount == 0) return;
        creditedReserves += amount;
        feeIncome += amount;
        emit InsuranceAccountingUpdated(amount, reportedBadDebt, outstandingBadDebt());
    }

    function recordBadDebt(uint256 amount) external onlyManager {
        if (amount == 0) return;
        reportedBadDebt += amount;
        emit InsuranceAccountingUpdated(0, amount, outstandingBadDebt());
    }

    function coverBadDebt(uint256 amount) external onlyGovernor {
        if (amount == 0) revert QuartzErrors.InvalidAmount();
        uint256 outstanding = outstandingBadDebt();
        if (amount > outstanding) amount = outstanding;
        coveredBadDebt += amount;
        collateralToken.safeTransfer(address(0x000000000000000000000000000000000000dEaD), amount);
        emit InsuranceAccountingUpdated(0, reportedBadDebt, outstandingBadDebt());
    }

    function outstandingBadDebt() public view returns (uint256) {
        if (reportedBadDebt <= coveredBadDebt) return 0;
        return reportedBadDebt - coveredBadDebt;
    }

    function balance() external view returns (uint256) {
        return IERC20(collateralToken).balanceOf(address(this));
    }
}
