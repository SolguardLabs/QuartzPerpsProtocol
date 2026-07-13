// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";

import { QuartzAccessController } from "../../src/access/QuartzAccessController.sol";
import { CollateralVault } from "../../src/assets/CollateralVault.sol";
import { FundingEngine } from "../../src/core/FundingEngine.sol";
import { InsuranceFund } from "../../src/core/InsuranceFund.sol";
import { PositionBook } from "../../src/core/PositionBook.sol";
import { QuartzPerpsProtocol } from "../../src/QuartzPerpsProtocol.sol";
import { OracleRouter } from "../../src/oracle/OracleRouter.sol";
import { RiskEngine } from "../../src/risk/RiskEngine.sol";
import { QuartzTypes } from "../../src/types/QuartzTypes.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

abstract contract QuartzFixture is Test {
    bytes32 internal constant ETH_ORACLE_ID = keccak256("ETH-USD-PERP");
    uint256 internal constant ETH_MARKET = 1;
    uint256 internal constant INITIAL_PRICE = 2000 ether;
    uint256 internal constant USER_BALANCE = 250_000 ether;

    address internal alice;
    address internal bob;
    address internal carol;

    MockERC20 internal collateral;
    QuartzAccessController internal accessController;
    CollateralVault internal collateralVault;
    OracleRouter internal oracleRouter;
    FundingEngine internal fundingEngine;
    RiskEngine internal riskEngine;
    PositionBook internal positionBook;
    InsuranceFund internal insuranceFund;
    QuartzPerpsProtocol internal protocol;

    function setUp() public virtual {
        vm.warp(10 days);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        collateral = new MockERC20("Quartz USD", "qUSD", 18);
        accessController = new QuartzAccessController(address(this));
        collateralVault = new CollateralVault(address(accessController), address(collateral));
        oracleRouter = new OracleRouter(address(accessController));
        fundingEngine = new FundingEngine(address(accessController));
        riskEngine = new RiskEngine(address(accessController));
        positionBook = new PositionBook(address(accessController));
        insuranceFund = new InsuranceFund(address(accessController), address(collateral));

        protocol = new QuartzPerpsProtocol(
            QuartzTypes.DeploymentConfig({
                collateralToken: address(collateral),
                accessController: address(accessController),
                collateralVault: address(collateralVault),
                oracleRouter: address(oracleRouter),
                fundingEngine: address(fundingEngine),
                riskEngine: address(riskEngine),
                positionBook: address(positionBook),
                insuranceFund: address(insuranceFund)
            })
        );

        accessController.grantRole(QuartzTypes.MANAGER_ROLE, address(protocol));
        accessController.grantRole(QuartzTypes.MANAGER_ROLE, address(this));

        oracleRouter.configureFeed(ETH_ORACLE_ID, 100 ether, 20_000 ether, 2 days);
        oracleRouter.reportPrice(ETH_ORACLE_ID, INITIAL_PRICE);

        riskEngine.configureMarket(
            ETH_MARKET,
            QuartzTypes.MarketConfig({
                enabled: true,
                oracleId: ETH_ORACLE_ID,
                symbol: "ETH-PERP",
                maxOracleAge: 2 days,
                minTradeSizeX18: uint128(0.1 ether),
                minMargin: uint128(100 ether),
                maxOpenInterestX18: uint128(10_000 ether),
                maxSkewX18: uint128(7500 ether),
                maxLeverageX18: uint64(10 ether),
                maintenanceMarginRatioX18: uint64(62_500_000_000_000_000),
                liquidationFeeRatioX18: uint64(5_000_000_000_000_000),
                fundingVelocityX18: uint64(2 ether)
            })
        );

        fundingEngine.configureMarket(ETH_MARKET, int256(2 ether), 1 hours);

        _prepare(alice);
        _prepare(bob);
        _prepare(carol);
    }

    function _prepare(address user) internal {
        collateral.mint(user, USER_BALANCE);
        vm.prank(user);
        collateral.approve(address(collateralVault), type(uint256).max);
    }

    function _openLong(address trader, uint256 sizeX18, uint256 marginAmount)
        internal
        returns (QuartzTypes.Position memory)
    {
        vm.prank(trader);
        protocol.openPosition(
            QuartzTypes.OpenPositionParams({
                marketId: ETH_MARKET,
                sizeDelta: int128(uint128(sizeX18)),
                marginAmount: marginAmount,
                acceptablePriceX18: INITIAL_PRICE + 1 ether
            })
        );
        return protocol.position(trader, ETH_MARKET);
    }

    function _openShort(address trader, uint256 sizeX18, uint256 marginAmount)
        internal
        returns (QuartzTypes.Position memory)
    {
        vm.prank(trader);
        protocol.openPosition(
            QuartzTypes.OpenPositionParams({
                marketId: ETH_MARKET,
                sizeDelta: -int128(uint128(sizeX18)),
                marginAmount: marginAmount,
                acceptablePriceX18: INITIAL_PRICE - 1 ether
            })
        );
        return protocol.position(trader, ETH_MARKET);
    }

    function _setPrice(uint256 priceX18) internal {
        oracleRouter.reportPrice(ETH_ORACLE_ID, priceX18);
    }
}
