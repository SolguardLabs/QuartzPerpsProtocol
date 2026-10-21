// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "../access/QuartzAccessController.sol";
import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title SettlementLedger
/// @notice Append-only settlement receipt index for downstream reconciliation.
contract SettlementLedger {
    enum SettlementKind {
        MarginDeposit,
        MarginWithdrawal,
        FundingSettlement,
        RealizedPnl,
        LiquidationReward,
        InsuranceCredit,
        BadDebt
    }

    struct SettlementReceipt {
        uint256 id;
        SettlementKind kind;
        address trader;
        address counterparty;
        uint256 marketId;
        int256 signedAmount;
        uint256 collateralAmount;
        uint48 timestamp;
        bytes32 refId;
    }

    QuartzAccessController public immutable accessController;

    uint256 public nextReceiptId = 1;

    mapping(uint256 id => SettlementReceipt receipt) private _receipts;
    mapping(address trader => uint256[] ids) private _receiptsByTrader;
    mapping(uint256 marketId => uint256[] ids) private _receiptsByMarket;

    event SettlementRecorded(
        uint256 indexed id,
        SettlementKind indexed kind,
        address indexed trader,
        uint256 marketId,
        int256 signedAmount,
        uint256 collateralAmount,
        bytes32 refId
    );

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

    function record(
        SettlementKind kind,
        address trader,
        address counterparty,
        uint256 marketId,
        int256 signedAmount,
        uint256 collateralAmount,
        bytes32 refId
    ) external onlyManager returns (uint256 id) {
        if (trader == address(0)) revert QuartzErrors.ZeroAddress();
        if (marketId == 0) revert QuartzErrors.UnknownMarket(marketId);

        id = nextReceiptId++;
        SettlementReceipt memory entry = SettlementReceipt({
            id: id,
            kind: kind,
            trader: trader,
            counterparty: counterparty,
            marketId: marketId,
            signedAmount: signedAmount,
            collateralAmount: collateralAmount,
            timestamp: uint48(block.timestamp),
            refId: refId
        });
        _receipts[id] = entry;
        _receiptsByTrader[trader].push(id);
        _receiptsByMarket[marketId].push(id);

        emit SettlementRecorded(id, kind, trader, marketId, signedAmount, collateralAmount, refId);
    }

    function recordBatch(SettlementReceipt[] calldata receipts)
        external
        onlyManager
        returns (uint256 firstId, uint256 lastId)
    {
        if (receipts.length == 0) revert QuartzErrors.InvalidAmount();
        firstId = nextReceiptId;
        for (uint256 i = 0; i < receipts.length; i++) {
            SettlementReceipt calldata item = receipts[i];
            if (item.trader == address(0)) revert QuartzErrors.ZeroAddress();
            uint256 id = nextReceiptId++;
            SettlementReceipt memory stored = SettlementReceipt({
                id: id,
                kind: item.kind,
                trader: item.trader,
                counterparty: item.counterparty,
                marketId: item.marketId,
                signedAmount: item.signedAmount,
                collateralAmount: item.collateralAmount,
                timestamp: uint48(block.timestamp),
                refId: item.refId
            });
            _receipts[id] = stored;
            _receiptsByTrader[item.trader].push(id);
            _receiptsByMarket[item.marketId].push(id);
            emit SettlementRecorded(
                id,
                item.kind,
                item.trader,
                item.marketId,
                item.signedAmount,
                item.collateralAmount,
                item.refId
            );
        }
        lastId = nextReceiptId - 1;
    }

    function receipt(uint256 id) external view returns (SettlementReceipt memory) {
        return _receipts[id];
    }

    function traderReceiptIds(address trader) external view returns (uint256[] memory) {
        return _receiptsByTrader[trader];
    }

    function marketReceiptIds(uint256 marketId) external view returns (uint256[] memory) {
        return _receiptsByMarket[marketId];
    }

    function traderReceiptCount(address trader) external view returns (uint256) {
        return _receiptsByTrader[trader].length;
    }

    function marketReceiptCount(uint256 marketId) external view returns (uint256) {
        return _receiptsByMarket[marketId].length;
    }
}
