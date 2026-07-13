// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title SignedMath
/// @notice Helpers for signed notional, PnL, and funding calculations.
library SignedMath {
    function abs(int256 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -value : value);
    }

    function abs128(int128 value) internal pure returns (uint128) {
        return uint128(uint256(value < 0 ? -int256(value) : int256(value)));
    }

    function sign(int256 value) internal pure returns (int256) {
        if (value > 0) return 1;
        if (value < 0) return -1;
        return 0;
    }

    function sameDirection(int256 a, int256 b) internal pure returns (bool) {
        if (a == 0 || b == 0) return true;
        return (a > 0 && b > 0) || (a < 0 && b < 0);
    }

    function checkedInt128(int256 value) internal pure returns (int128) {
        if (value > type(int128).max || value < type(int128).min) revert();
        return int128(value);
    }

    function toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) revert();
        return int256(value);
    }

    function addDelta(uint256 base, int256 delta)
        internal
        pure
        returns (uint256 value, uint256 deficit)
    {
        if (delta >= 0) return (base + uint256(delta), 0);
        uint256 debit = abs(delta);
        if (debit > base) return (0, debit - base);
        return (base - debit, 0);
    }

    function bounded(int256 value, int256 lower, int256 upper) internal pure returns (int256) {
        if (value < lower) return lower;
        if (value > upper) return upper;
        return value;
    }

    function minSigned(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    function maxSigned(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }
}
