// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { HealthMonitor } from "../src/risk/HealthMonitor.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract HealthMonitorTest is QuartzFixture {
    function testBatchAndKeeperUseProjectedFundingState() public {
        _openLong(alice, 100 ether, 25_000 ether);
        HealthMonitor monitor = new HealthMonitor(
            address(fundingEngine),
            address(positionBook),
            address(oracleRouter),
            address(riskEngine)
        );

        vm.warp(block.timestamp + 30 days);
        _setPrice(INITIAL_PRICE);
        fundingEngine.accrueFunding(ETH_MARKET, 2 ether);

        HealthMonitor.HealthReport memory report = monitor.report(alice, ETH_MARKET);
        assertEq(uint8(report.storedBand), uint8(HealthMonitor.HealthBand.Healthy));
        assertEq(uint8(report.fundingAdjustedBand), uint8(HealthMonitor.HealthBand.BelowInitial));
        assertEq(report.fundingPreview.payment, int256(6000 ether));

        address[] memory traders = new address[](1);
        traders[0] = alice;
        HealthMonitor.HealthBand[] memory bands = monitor.batchBands(traders, ETH_MARKET);
        assertEq(uint8(bands[0]), uint8(HealthMonitor.HealthBand.BelowInitial));
        assertTrue(monitor.needsKeeper(alice, ETH_MARKET));
    }

    function testEmptyAccountRequiresNoKeeperAction() public {
        HealthMonitor monitor = new HealthMonitor(
            address(fundingEngine),
            address(positionBook),
            address(oracleRouter),
            address(riskEngine)
        );
        assertFalse(monitor.needsKeeper(carol, ETH_MARKET));
        assertEq(
            uint8(monitor.report(carol, ETH_MARKET).fundingAdjustedBand),
            uint8(HealthMonitor.HealthBand.Empty)
        );
    }
}
