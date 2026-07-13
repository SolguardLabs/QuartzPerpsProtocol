// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzTypes } from "../types/QuartzTypes.sol";

interface IQuartzPerpsProtocol {
    function openPosition(QuartzTypes.OpenPositionParams calldata params) external;

    function increasePosition(QuartzTypes.IncreasePositionParams calldata params) external;

    function decreasePosition(QuartzTypes.DecreasePositionParams calldata params) external;

    function depositMargin(uint256 marketId, uint256 amount) external;

    function withdrawMargin(QuartzTypes.WithdrawalRequest calldata request) external;

    function liquidate(address trader, uint256 marketId, address receiver)
        external
        returns (QuartzTypes.LiquidationResult memory result);

    function position(address trader, uint256 marketId)
        external
        view
        returns (QuartzTypes.Position memory);
}
