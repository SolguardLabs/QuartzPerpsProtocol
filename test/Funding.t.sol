// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract FundingTest is QuartzFixture {
    function testFundingSettlesBeforePositionIncrease() public {
        _openLong(alice, 5 ether, 2000 ether);

        fundingEngine.pushFundingDelta(ETH_MARKET, int256(0.1 ether));

        vm.prank(alice);
        protocol.increasePosition(
            QuartzTypes.IncreasePositionParams({
                marketId: ETH_MARKET,
                sizeDelta: int128(int256(1 ether)),
                marginAmount: 600 ether,
                acceptablePriceX18: INITIAL_PRICE + 1 ether
            })
        );

        QuartzTypes.Position memory position_ = protocol.position(alice, ETH_MARKET);
        assertEq(position_.size, int128(int256(6 ether)));
        assertEq(position_.margin, 2000 ether - 0.5 ether + 600 ether);
        assertEq(position_.lastFundingIndexX18, int256(0.1 ether));
    }

    function testFundingCanBeAccruedFromElapsedRate() public {
        _openShort(bob, 4 ether, 2000 ether);
        vm.warp(block.timestamp + 2 hours);

        fundingEngine.accrueFunding(ETH_MARKET, int256(0.24 ether));

        QuartzTypes.FundingPreview memory preview =
            fundingEngine.previewPayment(ETH_MARKET, -int128(int256(4 ether)), 0);
        assertEq(preview.currentIndexX18, int256(0.02 ether));
        assertEq(preview.payment, -int256(0.08 ether));
    }
}
