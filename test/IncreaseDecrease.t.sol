// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract IncreaseDecreaseTest is QuartzFixture {
    function testIncreasePositionUpdatesAverageEntryAndExposure() public {
        _openLong(alice, 1 ether, 500 ether);
        _setPrice(2200 ether);

        vm.prank(alice);
        protocol.increasePosition(
            QuartzTypes.IncreasePositionParams({
                marketId: ETH_MARKET,
                sizeDelta: int128(int256(1 ether)),
                marginAmount: 400 ether,
                acceptablePriceX18: 2250 ether
            })
        );

        QuartzTypes.Position memory position_ = protocol.position(alice, ETH_MARKET);
        assertEq(position_.size, int128(int256(2 ether)));
        assertEq(position_.margin, 900 ether);
        assertEq(position_.entryPriceX18, 2100 ether);

        QuartzTypes.MarketExposure memory exposure = positionBook.exposure(ETH_MARKET);
        assertEq(exposure.longOpenInterestX18, 2 ether);
        assertEq(exposure.skewX18, int128(int256(2 ether)));
    }

    function testDecreasePositionRealizesPositivePnl() public {
        _openLong(alice, 2 ether, 1000 ether);
        _setPrice(2250 ether);

        vm.prank(alice);
        protocol.decreasePosition(
            QuartzTypes.DecreasePositionParams({
                marketId: ETH_MARKET,
                sizeAmountX18: uint128(1 ether),
                acceptablePriceX18: 2200 ether,
                receiver: alice
            })
        );

        QuartzTypes.Position memory position_ = protocol.position(alice, ETH_MARKET);
        assertEq(position_.size, int128(int256(1 ether)));
        assertEq(position_.margin, 1250 ether);
        assertEq(position_.realizedPnl, 250 ether);
    }
}
