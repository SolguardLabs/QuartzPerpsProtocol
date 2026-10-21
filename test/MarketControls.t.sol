// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract MarketControlsTest is QuartzFixture {
    function testWithdrawalRespectsInitialMarginAtCurrentPrice() public {
        _openLong(alice, 2 ether, 1000 ether);
        uint256 balanceBefore = collateral.balanceOf(alice);

        vm.expectRevert();
        vm.prank(alice);
        protocol.withdrawMargin(
            QuartzTypes.WithdrawalRequest({
                marketId: ETH_MARKET, amount: 700 ether, receiver: alice
            })
        );

        assertEq(protocol.position(alice, ETH_MARKET).margin, 1000 ether);
        assertEq(collateral.balanceOf(alice), balanceBefore);
    }

    function testStaleOraclePreventsOpeningPosition() public {
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert();
        vm.prank(alice);
        protocol.openPosition(
            QuartzTypes.OpenPositionParams({
                marketId: ETH_MARKET,
                sizeDelta: int128(int256(1 ether)),
                marginAmount: 1000 ether,
                acceptablePriceX18: INITIAL_PRICE + 1 ether
            })
        );
    }
}
