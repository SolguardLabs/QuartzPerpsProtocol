// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";

import { QuartzAccessController } from "../src/access/QuartzAccessController.sol";
import { CollateralVault } from "../src/assets/CollateralVault.sol";
import { FeeLedger } from "../src/core/FeeLedger.sol";
import { FundingEngine } from "../src/core/FundingEngine.sol";
import { InsuranceFund } from "../src/core/InsuranceFund.sol";
import { LiquidationQueue } from "../src/core/LiquidationQueue.sol";
import { PositionBook } from "../src/core/PositionBook.sol";
import { SettlementLedger } from "../src/core/SettlementLedger.sol";
import { QuartzLens } from "../src/lens/QuartzLens.sol";
import { OracleRouter } from "../src/oracle/OracleRouter.sol";
import { HealthMonitor } from "../src/risk/HealthMonitor.sol";
import { RiskEngine } from "../src/risk/RiskEngine.sol";
import { RiskParameterHistory } from "../src/risk/RiskParameterHistory.sol";
import { ScenarioEngine } from "../src/risk/ScenarioEngine.sol";
import { QuartzPerpsProtocol } from "../src/QuartzPerpsProtocol.sol";
import { QuartzTypes } from "../src/types/QuartzTypes.sol";

contract DeployQuartz is Script {
    struct Deployment {
        QuartzAccessController accessController;
        CollateralVault collateralVault;
        OracleRouter oracleRouter;
        FundingEngine fundingEngine;
        RiskEngine riskEngine;
        PositionBook positionBook;
        InsuranceFund insuranceFund;
        QuartzPerpsProtocol protocol;
        QuartzLens lens;
        HealthMonitor healthMonitor;
        ScenarioEngine scenarioEngine;
        LiquidationQueue liquidationQueue;
        SettlementLedger settlementLedger;
        FeeLedger feeLedger;
        RiskParameterHistory riskHistory;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        address finalOwner = vm.envOr("QUARTZ_OWNER", deployer);

        address governor = vm.envOr("QUARTZ_GOVERNOR", finalOwner);
        address keeper = vm.envOr("QUARTZ_KEEPER", governor);
        address reporter = vm.envOr("QUARTZ_REPORTER", governor);
        address guardian = vm.envOr("QUARTZ_GUARDIAN", governor);
        address liquidator = vm.envOr("QUARTZ_LIQUIDATOR", governor);

        vm.startBroadcast(deployerKey);

        deployment.accessController = new QuartzAccessController(deployer);
        deployment.collateralVault =
            new CollateralVault(address(deployment.accessController), collateralToken);
        deployment.oracleRouter = new OracleRouter(address(deployment.accessController));
        deployment.fundingEngine = new FundingEngine(address(deployment.accessController));
        deployment.riskEngine = new RiskEngine(address(deployment.accessController));
        deployment.positionBook = new PositionBook(address(deployment.accessController));
        deployment.insuranceFund =
            new InsuranceFund(address(deployment.accessController), collateralToken);

        deployment.protocol = new QuartzPerpsProtocol(
            QuartzTypes.DeploymentConfig({
                collateralToken: collateralToken,
                accessController: address(deployment.accessController),
                collateralVault: address(deployment.collateralVault),
                oracleRouter: address(deployment.oracleRouter),
                fundingEngine: address(deployment.fundingEngine),
                riskEngine: address(deployment.riskEngine),
                positionBook: address(deployment.positionBook),
                insuranceFund: address(deployment.insuranceFund)
            })
        );

        deployment.accessController
            .grantRole(QuartzTypes.MANAGER_ROLE, address(deployment.protocol));
        _grantRoleIfSet(deployment.accessController, QuartzTypes.GOVERNOR_ROLE, governor);
        _grantRoleIfSet(deployment.accessController, QuartzTypes.KEEPER_ROLE, keeper);
        _grantRoleIfSet(deployment.accessController, QuartzTypes.REPORTER_ROLE, reporter);
        _grantRoleIfSet(deployment.accessController, QuartzTypes.GUARDIAN_ROLE, guardian);
        _grantRoleIfSet(deployment.accessController, QuartzTypes.LIQUIDATOR_ROLE, liquidator);

        _configureInitialMarket(deployment);

        deployment.lens = new QuartzLens(
            address(deployment.oracleRouter),
            address(deployment.fundingEngine),
            address(deployment.riskEngine),
            address(deployment.positionBook)
        );
        deployment.healthMonitor = new HealthMonitor(
            address(deployment.fundingEngine),
            address(deployment.positionBook),
            address(deployment.oracleRouter),
            address(deployment.riskEngine)
        );
        deployment.scenarioEngine = new ScenarioEngine(
            address(deployment.fundingEngine),
            address(deployment.positionBook),
            address(deployment.oracleRouter),
            address(deployment.riskEngine)
        );
        deployment.liquidationQueue = new LiquidationQueue(
            address(deployment.accessController),
            address(deployment.riskEngine),
            address(deployment.oracleRouter),
            address(deployment.positionBook)
        );
        deployment.settlementLedger = new SettlementLedger(address(deployment.accessController));
        deployment.feeLedger = new FeeLedger(address(deployment.accessController), collateralToken);
        deployment.riskHistory = new RiskParameterHistory(address(deployment.accessController));
        deployment.riskHistory.recordConfig(_marketId(), _marketConfig());

        if (finalOwner != deployer) {
            deployment.accessController.transferOwnership(finalOwner);
        }

        vm.stopBroadcast();
    }

    function _configureInitialMarket(Deployment memory deployment) internal {
        bytes32 oracleId = _oracleId();
        uint256 marketId = _marketId();

        deployment.oracleRouter
            .configureFeed(
                oracleId,
                vm.envOr("QUARTZ_MIN_PRICE_X18", uint256(100 ether)),
                vm.envOr("QUARTZ_MAX_PRICE_X18", uint256(20_000 ether)),
                uint48(vm.envOr("QUARTZ_MAX_ORACLE_AGE", uint256(2 days)))
            );
        deployment.oracleRouter
            .reportPrice(oracleId, vm.envOr("QUARTZ_INITIAL_PRICE_X18", uint256(2000 ether)));

        deployment.riskEngine.configureMarket(marketId, _marketConfig());
        deployment.fundingEngine
            .configureMarket(
                marketId,
                int256(vm.envOr("QUARTZ_MAX_FUNDING_RATE_X18", uint256(2 ether))),
                uint48(vm.envOr("QUARTZ_MIN_FUNDING_INTERVAL", uint256(1 hours)))
            );
    }

    function _marketConfig() internal view returns (QuartzTypes.MarketConfig memory) {
        return QuartzTypes.MarketConfig({
            enabled: vm.envOr("QUARTZ_MARKET_ENABLED", true),
            oracleId: _oracleId(),
            symbol: vm.envOr("QUARTZ_MARKET_SYMBOL", string("ETH-PERP")),
            maxOracleAge: uint48(vm.envOr("QUARTZ_MAX_ORACLE_AGE", uint256(2 days))),
            minTradeSizeX18: uint128(vm.envOr("QUARTZ_MIN_TRADE_SIZE_X18", uint256(0.1 ether))),
            minMargin: uint128(vm.envOr("QUARTZ_MIN_MARGIN", uint256(100 ether))),
            maxOpenInterestX18: uint128(
                vm.envOr("QUARTZ_MAX_OPEN_INTEREST_X18", uint256(10_000 ether))
            ),
            maxSkewX18: uint128(vm.envOr("QUARTZ_MAX_SKEW_X18", uint256(7500 ether))),
            maxLeverageX18: uint64(vm.envOr("QUARTZ_MAX_LEVERAGE_X18", uint256(10 ether))),
            maintenanceMarginRatioX18: uint64(
                vm.envOr("QUARTZ_MAINTENANCE_MARGIN_RATIO_X18", uint256(0.0625 ether))
            ),
            liquidationFeeRatioX18: uint64(
                vm.envOr("QUARTZ_LIQUIDATION_FEE_RATIO_X18", uint256(0.005 ether))
            ),
            fundingVelocityX18: uint64(vm.envOr("QUARTZ_FUNDING_VELOCITY_X18", uint256(2 ether)))
        });
    }

    function _marketId() internal view returns (uint256) {
        return vm.envOr("QUARTZ_MARKET_ID", uint256(1));
    }

    function _oracleId() internal view returns (bytes32) {
        return keccak256(bytes(vm.envOr("QUARTZ_ORACLE_KEY", string("ETH-USD-PERP"))));
    }

    function _grantRoleIfSet(QuartzAccessController accessController, bytes32 role, address account)
        internal
    {
        if (account != address(0) && !accessController.hasRole(role, account)) {
            accessController.grantRole(role, account);
        }
    }
}
