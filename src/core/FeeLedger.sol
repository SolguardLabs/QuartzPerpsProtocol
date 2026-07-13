// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title FeeLedger
/// @notice Optional accounting module for trade fees, rebates, and treasury withdrawals.
contract FeeLedger {
    using SafeTransferLib for address;

    struct FeeConfig {
        bool enabled;
        uint32 makerFeeBps;
        uint32 takerFeeBps;
        uint32 liquidationFeeBps;
        uint32 referralRebateBps;
        address treasury;
    }

    struct AccruedFees {
        uint256 makerFees;
        uint256 takerFees;
        uint256 liquidationFees;
        uint256 referralRebates;
        uint256 withdrawn;
    }

    QuartzAccessController public immutable accessController;
    address public immutable collateralToken;

    mapping(uint256 marketId => FeeConfig config) private _feeConfigs;
    mapping(uint256 marketId => AccruedFees accrued) private _accruedFees;
    mapping(address referrer => uint256 amount) public referralAccruals;

    event FeeConfigUpdated(uint256 indexed marketId, FeeConfig config);
    event TradeFeeRecorded(
        uint256 indexed marketId,
        address indexed trader,
        address indexed referrer,
        uint256 makerFee,
        uint256 takerFee,
        uint256 rebate
    );
    event LiquidationFeeRecorded(uint256 indexed marketId, address indexed liquidator, uint256 fee);
    event FeesWithdrawn(uint256 indexed marketId, address indexed receiver, uint256 amount);

    constructor(address accessController_, address collateralToken_) {
        if (accessController_ == address(0) || collateralToken_ == address(0)) {
            revert QuartzErrors.ZeroAddress();
        }
        accessController = QuartzAccessController(accessController_);
        collateralToken = collateralToken_;
    }

    modifier onlyRole(bytes32 role) {
        if (!accessController.hasRole(role, msg.sender)) {
            revert QuartzErrors.Unauthorized(role, msg.sender);
        }
        _;
    }

    function configureFees(uint256 marketId, FeeConfig calldata config)
        external
        onlyRole(QuartzTypes.GOVERNOR_ROLE)
    {
        if (marketId == 0) revert QuartzErrors.UnknownMarket(marketId);
        if (config.treasury == address(0)) revert QuartzErrors.ZeroAddress();
        if (
            config.makerFeeBps > 1000 || config.takerFeeBps > 1000
                || config.liquidationFeeBps > 2000 || config.referralRebateBps > config.takerFeeBps
        ) {
            revert QuartzErrors.InvalidAmount();
        }
        _feeConfigs[marketId] = config;
        emit FeeConfigUpdated(marketId, config);
    }

    function recordTradeFee(
        uint256 marketId,
        address trader,
        address referrer,
        uint256 notional,
        bool maker
    ) external onlyRole(QuartzTypes.MANAGER_ROLE) returns (uint256 chargedFee, uint256 rebate) {
        FeeConfig memory config = _feeConfigs[marketId];
        if (!config.enabled) return (0, 0);
        uint256 feeBps = maker ? config.makerFeeBps : config.takerFeeBps;
        chargedFee = (notional * feeBps) / QuartzTypes.BPS;
        if (chargedFee == 0) return (0, 0);

        if (!maker && referrer != address(0) && referrer != trader) {
            rebate = (notional * config.referralRebateBps) / QuartzTypes.BPS;
            referralAccruals[referrer] += rebate;
            _accruedFees[marketId].referralRebates += rebate;
        }

        if (maker) {
            _accruedFees[marketId].makerFees += chargedFee;
            emit TradeFeeRecorded(marketId, trader, referrer, chargedFee, 0, rebate);
        } else {
            _accruedFees[marketId].takerFees += chargedFee;
            emit TradeFeeRecorded(marketId, trader, referrer, 0, chargedFee, rebate);
        }
    }

    function recordLiquidationFee(uint256 marketId, address liquidator, uint256 fee)
        external
        onlyRole(QuartzTypes.MANAGER_ROLE)
    {
        if (fee == 0) return;
        _accruedFees[marketId].liquidationFees += fee;
        emit LiquidationFeeRecorded(marketId, liquidator, fee);
    }

    function withdrawMarketFees(uint256 marketId, address receiver, uint256 amount)
        external
        onlyRole(QuartzTypes.GOVERNOR_ROLE)
    {
        if (receiver == address(0)) revert QuartzErrors.ZeroAddress();
        uint256 available = withdrawableFees(marketId);
        if (amount > available) amount = available;
        if (amount == 0) revert QuartzErrors.InvalidAmount();
        _accruedFees[marketId].withdrawn += amount;
        collateralToken.safeTransfer(receiver, amount);
        emit FeesWithdrawn(marketId, receiver, amount);
    }

    function claimReferralFees(address receiver) external returns (uint256 amount) {
        if (receiver == address(0)) revert QuartzErrors.ZeroAddress();
        amount = referralAccruals[msg.sender];
        if (amount == 0) revert QuartzErrors.InvalidAmount();
        referralAccruals[msg.sender] = 0;
        collateralToken.safeTransfer(receiver, amount);
    }

    function feeConfig(uint256 marketId) external view returns (FeeConfig memory) {
        return _feeConfigs[marketId];
    }

    function accruedFees(uint256 marketId) external view returns (AccruedFees memory) {
        return _accruedFees[marketId];
    }

    function withdrawableFees(uint256 marketId) public view returns (uint256) {
        AccruedFees memory accrued = _accruedFees[marketId];
        uint256 gross = accrued.makerFees + accrued.takerFees + accrued.liquidationFees;
        uint256 reserved = accrued.referralRebates + accrued.withdrawn;
        if (gross <= reserved) return 0;
        return gross - reserved;
    }
}
