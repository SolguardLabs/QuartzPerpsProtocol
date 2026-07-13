// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../src/types/QuartzTypes.sol";
import { QuartzFixture } from "./helpers/QuartzFixture.sol";

contract WithdrawMarginTest is QuartzFixture {
    function testWithdrawMarginAfterDeposit() public {
        vm.prank(alice);
        protocol.depositMargin(ETH_MARKET, 1000 ether);

        uint256 aliceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        protocol.withdrawMargin(
            QuartzTypes.WithdrawalRequest({
                marketId: ETH_MARKET, amount: 250 ether, receiver: alice
            })
        );

        QuartzTypes.Position memory position_ = protocol.position(alice, ETH_MARKET);
        assertEq(position_.margin, 750 ether);
        assertEq(collateral.balanceOf(alice), aliceBefore + 250 ether);
    }

    function testWithdrawMarginFromHealthyOpenPosition() public {
        _openLong(alice, 2 ether, 2000 ether);
        uint256 aliceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        protocol.withdrawMargin(
            QuartzTypes.WithdrawalRequest({
                marketId: ETH_MARKET, amount: 500 ether, receiver: alice
            })
        );

        QuartzTypes.Position memory position_ = protocol.position(alice, ETH_MARKET);
        assertEq(position_.margin, 1500 ether);
        assertEq(position_.size, int128(int256(2 ether)));
        assertEq(collateral.balanceOf(alice), aliceBefore + 500 ether);
    }
}
