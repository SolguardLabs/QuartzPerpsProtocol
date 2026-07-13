// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract LiquidationTest is QuartzFixture {
    function testPriceMoveAllowsLiquidation() public {
        _openLong(alice, 5 ether, 1150 ether);
        _setPrice(1780 ether);

        uint256 bobBefore = collateral.balanceOf(bob);
        QuartzTypes.LiquidationResult memory result = protocol.liquidate(alice, ETH_MARKET, bob);

        assertEq(result.trader, alice);
        assertEq(result.reward, 44.5 ether);
        assertEq(result.insuranceCredit, 5.5 ether);
        assertEq(collateral.balanceOf(bob), bobBefore + result.reward);

        QuartzTypes.Position memory closed = protocol.position(alice, ETH_MARKET);
        assertEq(closed.size, 0);
        assertEq(closed.margin, 0);
        assertEq(uint8(closed.status), uint8(QuartzTypes.PositionStatus.Liquidated));
        assertGt(insuranceFund.creditedReserves(), 0);
    }

    function testLiquidationAccountsForFundingBeforeCloseout() public {
        _openLong(alice, 3 ether, 700 ether);
        fundingEngine.pushFundingDelta(ETH_MARKET, int256(0.05 ether));
        _setPrice(1850 ether);

        QuartzTypes.LiquidationResult memory result = protocol.liquidate(alice, ETH_MARKET, carol);
        assertEq(result.badDebt, 0);

        QuartzTypes.Position memory closed = protocol.position(alice, ETH_MARKET);
        assertEq(closed.size, 0);
        assertEq(closed.margin, 0);
        assertEq(closed.lastFundingIndexX18, int256(0.05 ether));
    }
}
