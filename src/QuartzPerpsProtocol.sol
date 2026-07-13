// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzAccessController } from "./access/QuartzAccessController.sol";
import { CollateralVault } from "./assets/CollateralVault.sol";
import { FundingEngine } from "./core/FundingEngine.sol";
import { InsuranceFund } from "./core/InsuranceFund.sol";
import { PositionBook } from "./core/PositionBook.sol";
import { QuartzErrors } from "./errors/QuartzErrors.sol";
import { QuartzEvents } from "./events/QuartzEvents.sol";
import { IQuartzPerpsProtocol } from "./interfaces/IQuartzPerpsProtocol.sol";
import { FundingMath } from "./libraries/FundingMath.sol";
import { PositionMath } from "./libraries/PositionMath.sol";
import { SignedMath } from "./libraries/SignedMath.sol";
import { OracleRouter } from "./oracle/OracleRouter.sol";
import { RiskEngine } from "./risk/RiskEngine.sol";
import { QuartzTypes } from "./types/QuartzTypes.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

/// @title QuartzPerpsProtocol
/// @notice Isolated-margin perpetual futures entry point.
contract QuartzPerpsProtocol is IQuartzPerpsProtocol, QuartzEvents, ReentrancyGuard {
    using SignedMath for int256;

    QuartzAccessController public immutable accessController;
    CollateralVault public immutable collateralVault;
    OracleRouter public immutable oracleRouter;
    FundingEngine public immutable fundingEngine;
    RiskEngine public immutable riskEngine;
    PositionBook public immutable positionBook;
    InsuranceFund public immutable insuranceFund;

    constructor(QuartzTypes.DeploymentConfig memory config) {
        if (
            config.accessController == address(0) || config.collateralVault == address(0)
                || config.oracleRouter == address(0) || config.fundingEngine == address(0)
                || config.riskEngine == address(0) || config.positionBook == address(0)
                || config.insuranceFund == address(0)
        ) {
            revert QuartzErrors.ZeroAddress();
        }

        accessController = QuartzAccessController(config.accessController);
        collateralVault = CollateralVault(config.collateralVault);
        oracleRouter = OracleRouter(config.oracleRouter);
        fundingEngine = FundingEngine(config.fundingEngine);
        riskEngine = RiskEngine(config.riskEngine);
        positionBook = PositionBook(config.positionBook);
        insuranceFund = InsuranceFund(config.insuranceFund);
    }

    modifier whenNotPaused() {
        if (accessController.paused()) revert QuartzErrors.ProtocolPaused();
        _;
    }

    function position(address trader, uint256 marketId)
        external
        view
        returns (QuartzTypes.Position memory)
    {
        return positionBook.position(trader, marketId);
    }

    function depositMargin(uint256 marketId, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert QuartzErrors.InvalidAmount();
        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(marketId);

        QuartzTypes.Position memory account = positionBook.position(msg.sender, marketId);
        (account,) = _settleFunding(msg.sender, marketId, account);

        collateralVault.collect(msg.sender, amount);
        account = _ensureAccount(account, marketId);
        account.margin = _toUint128(uint256(account.margin) + amount);
        account.lastUpdated = uint48(block.timestamp);

        positionBook.storePosition(msg.sender, marketId, account);
        emit MarginDeposited(msg.sender, marketId, amount, account.margin);

        market;
    }

    function openPosition(QuartzTypes.OpenPositionParams calldata params)
        external
        nonReentrant
        whenNotPaused
    {
        if (params.sizeDelta == 0) revert QuartzErrors.InvalidSize();
        if (params.marginAmount == 0) revert QuartzErrors.InvalidMargin();

        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(params.marketId);
        _validateTradeSize(market, params.sizeDelta);

        QuartzTypes.PriceData memory price = oracleRouter.getPrice(market.oracleId);
        _checkExecutionPrice(params.sizeDelta, price.priceX18, params.acceptablePriceX18);

        QuartzTypes.Position memory account = positionBook.position(msg.sender, params.marketId);
        if (account.exists && account.size != 0) {
            revert QuartzErrors.PositionExists(msg.sender, params.marketId);
        }

        collateralVault.collect(msg.sender, params.marginAmount);

        account = _ensureAccount(account, params.marketId);
        account.status = QuartzTypes.PositionStatus.Open;
        account.marginMode = QuartzTypes.MarginMode.Isolated;
        account.size = params.sizeDelta;
        account.margin = _toUint128(uint256(account.margin) + params.marginAmount);
        account.entryPriceX18 = _toUint128(price.priceX18);
        account.lastFundingIndexX18 = fundingEngine.currentIndex(params.marketId);
        account.lastUpdated = uint48(block.timestamp);

        riskEngine.validateExposure(
            params.marketId, positionBook.exposure(params.marketId), 0, account.size
        );
        riskEngine.validateInitialMargin(params.marketId, account, price.priceX18);
        positionBook.storePosition(msg.sender, params.marketId, account);

        emit PositionOpened(
            msg.sender, params.marketId, account.size, account.margin, account.entryPriceX18
        );
    }

    function increasePosition(QuartzTypes.IncreasePositionParams calldata params)
        external
        nonReentrant
        whenNotPaused
    {
        if (params.sizeDelta == 0) revert QuartzErrors.InvalidSize();

        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(params.marketId);
        _validateTradeSize(market, params.sizeDelta);

        QuartzTypes.PriceData memory price = oracleRouter.getPrice(market.oracleId);
        _checkExecutionPrice(params.sizeDelta, price.priceX18, params.acceptablePriceX18);

        QuartzTypes.Position memory account = _requireOpenPosition(msg.sender, params.marketId);
        if (!SignedMath.sameDirection(account.size, params.sizeDelta)) {
            revert QuartzErrors.DirectionMismatch();
        }

        (account,) = _settleFunding(msg.sender, params.marketId, account);
        if (params.marginAmount > 0) {
            collateralVault.collect(msg.sender, params.marginAmount);
            account.margin = _toUint128(uint256(account.margin) + params.marginAmount);
        }

        int128 oldSize = account.size;
        int256 nextSize = int256(account.size) + int256(params.sizeDelta);
        account.size = SignedMath.checkedInt128(nextSize);
        if (PositionMath.absSize(account.size) <= PositionMath.absSize(oldSize)) {
            revert QuartzErrors.InvalidSize();
        }
        account.entryPriceX18 = _toUint128(
            PositionMath.nextEntryPrice(
                oldSize, account.entryPriceX18, params.sizeDelta, price.priceX18
            )
        );
        account.status = QuartzTypes.PositionStatus.Open;
        account.lastUpdated = uint48(block.timestamp);

        riskEngine.validateExposure(
            params.marketId, positionBook.exposure(params.marketId), oldSize, account.size
        );
        riskEngine.validateInitialMargin(params.marketId, account, price.priceX18);
        positionBook.storePosition(msg.sender, params.marketId, account);

        emit PositionIncreased(
            msg.sender,
            params.marketId,
            params.sizeDelta,
            account.size,
            account.margin,
            account.entryPriceX18
        );
    }

    function decreasePosition(QuartzTypes.DecreasePositionParams calldata params)
        external
        nonReentrant
        whenNotPaused
    {
        if (params.receiver == address(0)) revert QuartzErrors.InvalidReceiver();
        if (params.sizeAmountX18 == 0) revert QuartzErrors.InvalidSize();

        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(params.marketId);
        QuartzTypes.Position memory account = _requireOpenPosition(msg.sender, params.marketId);
        (account,) = _settleFunding(msg.sender, params.marketId, account);

        uint256 currentAbs = PositionMath.absSize(account.size);
        if (params.sizeAmountX18 > currentAbs) {
            revert QuartzErrors.ReduceExceedsPosition(params.sizeAmountX18, currentAbs);
        }

        QuartzTypes.PriceData memory price = oracleRouter.getPrice(market.oracleId);
        int128 executionDelta =
            PositionMath.tradeDirectionForReduction(account.size, params.sizeAmountX18);
        _checkExecutionPrice(executionDelta, price.priceX18, params.acceptablePriceX18);

        int128 oldSize = account.size;
        int256 realized = PositionMath.realizedPnlForReduction(
            account.size, account.entryPriceX18, price.priceX18, params.sizeAmountX18
        );
        (uint256 nextMargin, uint256 badDebt) =
            PositionMath.marginAfterPnl(account.margin, realized);
        if (badDebt > 0) insuranceFund.recordBadDebt(badDebt);

        account.realizedPnl += realized;
        account.margin = _toUint128(nextMargin);
        account.size = PositionMath.reduceSize(account.size, params.sizeAmountX18);
        account.lastUpdated = uint48(block.timestamp);
        if (account.size == 0) {
            account.status = QuartzTypes.PositionStatus.Closed;
            account.entryPriceX18 = 0;
        }

        riskEngine.validateExposure(
            params.marketId, positionBook.exposure(params.marketId), oldSize, account.size
        );
        positionBook.storePosition(msg.sender, params.marketId, account);

        emit PositionDecreased(
            msg.sender,
            params.marketId,
            params.sizeAmountX18,
            account.size,
            realized,
            account.margin
        );
    }

    function withdrawMargin(QuartzTypes.WithdrawalRequest calldata request)
        external
        nonReentrant
        whenNotPaused
    {
        if (request.receiver == address(0)) revert QuartzErrors.InvalidReceiver();
        if (request.amount == 0) revert QuartzErrors.InvalidAmount();

        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(request.marketId);
        QuartzTypes.Position memory account = positionBook.position(msg.sender, request.marketId);
        if (!account.exists) revert QuartzErrors.PositionNotFound(msg.sender, request.marketId);
        if (request.amount > account.margin) {
            revert QuartzErrors.InsufficientMargin(account.margin, request.amount);
        }

        QuartzTypes.PriceData memory price = oracleRouter.getPrice(market.oracleId);
        account.margin = _toUint128(uint256(account.margin) - request.amount);
        account.lastUpdated = uint48(block.timestamp);

        riskEngine.validateWithdrawal(request.marketId, account, price.priceX18);
        positionBook.storePosition(msg.sender, request.marketId, account);
        collateralVault.release(request.receiver, request.amount);

        emit MarginWithdrawn(
            msg.sender, request.marketId, request.receiver, request.amount, account.margin
        );
    }

    function liquidate(address trader, uint256 marketId, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (QuartzTypes.LiquidationResult memory result)
    {
        if (trader == address(0) || receiver == address(0)) {
            revert QuartzErrors.ZeroAddress();
        }

        QuartzTypes.MarketConfig memory market = riskEngine.requireEnabledMarket(marketId);
        QuartzTypes.Position memory account = _requireOpenPosition(trader, marketId);
        uint256 fundingBadDebt;
        (account, fundingBadDebt) = _settleFunding(trader, marketId, account);

        QuartzTypes.PriceData memory price = oracleRouter.getPrice(market.oracleId);
        QuartzTypes.RiskSnapshot memory snapshot =
            riskEngine.previewRisk(marketId, account, price.priceX18);
        if (!snapshot.liquidatable) {
            revert QuartzErrors.MaintenanceMarginSatisfied(
                snapshot.equity, snapshot.maintenanceMargin
            );
        }

        int256 closePnl =
            PositionMath.unrealizedPnl(account.size, account.entryPriceX18, price.priceX18);
        (uint256 marginAfterClose, uint256 pnlBadDebt) =
            PositionMath.marginAfterPnl(account.margin, closePnl);
        uint256 badDebt = fundingBadDebt + pnlBadDebt;
        if (pnlBadDebt > 0) insuranceFund.recordBadDebt(pnlBadDebt);

        uint256 reward = PositionMath.notional(account.size, price.priceX18);
        reward = _min(reward, snapshot.liquidationFee);
        reward = _min(reward, marginAfterClose);
        uint256 insuranceCredit = marginAfterClose - reward;

        QuartzTypes.Position memory closed = account;
        closed.status = QuartzTypes.PositionStatus.Liquidated;
        closed.size = 0;
        closed.margin = 0;
        closed.entryPriceX18 = 0;
        closed.realizedPnl += closePnl;
        closed.lastUpdated = uint48(block.timestamp);
        positionBook.storePosition(trader, marketId, closed);

        if (reward > 0) collateralVault.release(receiver, reward);
        if (insuranceCredit > 0) {
            collateralVault.release(address(insuranceFund), insuranceCredit);
            insuranceFund.recordCredit(insuranceCredit);
        }

        result = QuartzTypes.LiquidationResult({
            trader: trader,
            liquidator: msg.sender,
            marketId: marketId,
            priceX18: price.priceX18,
            closePnl: closePnl,
            reward: reward,
            insuranceCredit: insuranceCredit,
            badDebt: badDebt
        });

        emit PositionLiquidated(
            trader, msg.sender, marketId, closePnl, reward, insuranceCredit, badDebt
        );
    }

    function _settleFunding(address trader, uint256 marketId, QuartzTypes.Position memory account)
        internal
        returns (QuartzTypes.Position memory updated, uint256 badDebt)
    {
        updated = account;
        int256 currentIndex = fundingEngine.currentIndex(marketId);

        if (!updated.exists) {
            updated = _ensureAccount(updated, marketId);
            updated.lastFundingIndexX18 = currentIndex;
            return (updated, 0);
        }

        if (updated.size == 0) {
            updated.lastFundingIndexX18 = currentIndex;
            updated.lastUpdated = uint48(block.timestamp);
            positionBook.storePosition(trader, marketId, updated);
            return (updated, 0);
        }

        int256 payment =
            FundingMath.pendingPayment(updated.size, currentIndex, updated.lastFundingIndexX18);
        if (payment > 0) {
            uint256 debit = uint256(payment);
            if (debit > updated.margin) {
                badDebt = debit - updated.margin;
                updated.margin = 0;
                insuranceFund.recordBadDebt(badDebt);
            } else {
                updated.margin = _toUint128(uint256(updated.margin) - debit);
            }
        } else if (payment < 0) {
            uint256 credit = uint256(-payment);
            updated.margin = _toUint128(uint256(updated.margin) + credit);
        }

        updated.lastFundingIndexX18 = currentIndex;
        updated.lastUpdated = uint48(block.timestamp);
        positionBook.storePosition(trader, marketId, updated);
        emit FundingSettled(trader, marketId, payment, currentIndex, updated.margin);
    }

    function _ensureAccount(QuartzTypes.Position memory account, uint256 marketId)
        internal
        view
        returns (QuartzTypes.Position memory)
    {
        if (!account.exists) {
            account.exists = true;
            account.status = QuartzTypes.PositionStatus.Closed;
            account.marginMode = QuartzTypes.MarginMode.Isolated;
            account.openedAt = uint48(block.timestamp);
            account.lastUpdated = uint48(block.timestamp);
            account.lastFundingIndexX18 = fundingEngine.currentIndex(marketId);
        }
        return account;
    }

    function _requireOpenPosition(address trader, uint256 marketId)
        internal
        view
        returns (QuartzTypes.Position memory account)
    {
        account = positionBook.position(trader, marketId);
        if (!account.exists) revert QuartzErrors.PositionNotFound(trader, marketId);
        if (account.size == 0 || account.status != QuartzTypes.PositionStatus.Open) {
            revert QuartzErrors.PositionClosed(trader, marketId);
        }
    }

    function _validateTradeSize(QuartzTypes.MarketConfig memory market, int128 sizeDelta)
        internal
        pure
    {
        if (PositionMath.absSize(sizeDelta) < market.minTradeSizeX18) {
            revert QuartzErrors.InvalidSize();
        }
    }

    function _checkExecutionPrice(
        int128 signedTradeDelta,
        uint256 priceX18,
        uint256 acceptablePriceX18
    ) internal pure {
        if (acceptablePriceX18 == 0) return;
        if (signedTradeDelta > 0 && priceX18 > acceptablePriceX18) {
            revert QuartzErrors.Slippage(priceX18, acceptablePriceX18);
        }
        if (signedTradeDelta < 0 && priceX18 < acceptablePriceX18) {
            revert QuartzErrors.Slippage(priceX18, acceptablePriceX18);
        }
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert QuartzErrors.Overflow();
        return uint128(value);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
