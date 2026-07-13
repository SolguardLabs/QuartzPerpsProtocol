// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title FixedPointMath
/// @notice Small WAD/BPS math library for deterministic protocol accounting.
library FixedPointMath {
    uint256 internal constant WAD = QuartzTypes.WAD;
    uint256 internal constant BPS = QuartzTypes.BPS;

    function mulWad(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b) / WAD;
    }

    function mulWadUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return ((a * b) - 1) / WAD + 1;
    }

    function divWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * WAD) / b;
    }

    function divWadUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        return ((a * WAD) - 1) / b + 1;
    }

    function mulBps(uint256 a, uint256 bps) internal pure returns (uint256) {
        if (a == 0 || bps == 0) return 0;
        return (a * bps) / BPS;
    }

    function mulBpsUp(uint256 a, uint256 bps) internal pure returns (uint256) {
        if (a == 0 || bps == 0) return 0;
        return ((a * bps) - 1) / BPS + 1;
    }

    function percentOf(uint256 amount, uint256 ratioX18) internal pure returns (uint256) {
        return mulWad(amount, ratioX18);
    }

    function ratio(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return type(uint256).max;
        return divWad(numerator, denominator);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function clamp(uint256 value, uint256 lower, uint256 upper) internal pure returns (uint256) {
        if (value < lower) return lower;
        if (value > upper) return upper;
        return value;
    }

    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert();
        return uint128(value);
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = (x + 1) / 2;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }

    function annualize(uint256 rateX18, uint256 elapsed) internal pure returns (uint256) {
        return (rateX18 * elapsed) / QuartzTypes.YEAR;
    }

    function deannualize(uint256 annualRateX18, uint256 elapsed) internal pure returns (uint256) {
        return (annualRateX18 * elapsed) / QuartzTypes.YEAR;
    }
}
