// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzErrors } from "../errors/QuartzErrors.sol";

/// @title SafeTransferLib
/// @notice Minimal ERC-20 transfer helpers accepting tokens with or without boolean return values.
library SafeTransferLib {
    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(0xa9059cbb), to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert QuartzErrors.TransferFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(0x23b872dd), from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert QuartzErrors.TransferFailed();
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(0x095ea7b3), spender, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert QuartzErrors.TransferFailed();
        }
    }
}
