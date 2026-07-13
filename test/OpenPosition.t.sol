// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract OpenPositionTest is QuartzFixture {
    function testOpenPositionStoresInitialRiskState() public {
        uint256 aliceBefore = collateral.balanceOf(alice);

        QuartzTypes.Position memory position_ = _openLong(alice, 2 ether, 1000 ether);

        assertTrue(position_.exists);
        assertEq(uint8(position_.status), uint8(QuartzTypes.PositionStatus.Open));
        assertEq(position_.size, int128(int256(2 ether)));
        assertEq(position_.margin, 1000 ether);
        assertEq(position_.entryPriceX18, INITIAL_PRICE);
        assertEq(position_.lastFundingIndexX18, 0);
        assertEq(collateral.balanceOf(alice), aliceBefore - 1000 ether);
        assertEq(collateral.balanceOf(address(collateralVault)), 1000 ether);
    }

    function testOpenShortTracksMarketExposure() public {
        _openShort(bob, 3 ether, 2000 ether);

        QuartzTypes.MarketExposure memory exposure = positionBook.exposure(ETH_MARKET);
        assertEq(exposure.longOpenInterestX18, 0);
        assertEq(exposure.shortOpenInterestX18, 3 ether);
        assertEq(exposure.skewX18, -int128(int256(3 ether)));
    }
}
