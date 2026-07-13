// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { QuartzErrors } from "../errors/QuartzErrors.sol";
import { QuartzEvents } from "../events/QuartzEvents.sol";
import { QuartzTypes } from "../types/QuartzTypes.sol";

/// @title QuartzAccessController
/// @notice Compact role and pause controller shared by all protocol modules.
contract QuartzAccessController is QuartzEvents {
    address public owner;
    bool public paused;

    mapping(bytes32 role => mapping(address account => bool enabled)) private _roles;

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert QuartzErrors.ZeroAddress();
        owner = initialOwner;
        _grantRole(QuartzTypes.GOVERNOR_ROLE, initialOwner);
        _grantRole(QuartzTypes.GUARDIAN_ROLE, initialOwner);
        _grantRole(QuartzTypes.REPORTER_ROLE, initialOwner);
        _grantRole(QuartzTypes.KEEPER_ROLE, initialOwner);
        _grantRole(QuartzTypes.LIQUIDATOR_ROLE, initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert QuartzErrors.Unauthorized(bytes32(0), msg.sender);
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert QuartzErrors.Unauthorized(role, msg.sender);
        _;
    }

    function GOVERNOR_ROLE() external pure returns (bytes32) {
        return QuartzTypes.GOVERNOR_ROLE;
    }

    function KEEPER_ROLE() external pure returns (bytes32) {
        return QuartzTypes.KEEPER_ROLE;
    }

    function MANAGER_ROLE() external pure returns (bytes32) {
        return QuartzTypes.MANAGER_ROLE;
    }

    function LIQUIDATOR_ROLE() external pure returns (bytes32) {
        return QuartzTypes.LIQUIDATOR_ROLE;
    }

    function REPORTER_ROLE() external pure returns (bytes32) {
        return QuartzTypes.REPORTER_ROLE;
    }

    function GUARDIAN_ROLE() external pure returns (bytes32) {
        return QuartzTypes.GUARDIAN_ROLE;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return account == owner || _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyOwner {
        if (account == address(0)) revert QuartzErrors.ZeroAddress();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyOwner {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert QuartzErrors.ZeroAddress();
        owner = nextOwner;
        _grantRole(QuartzTypes.GOVERNOR_ROLE, nextOwner);
        _grantRole(QuartzTypes.GUARDIAN_ROLE, nextOwner);
    }

    function setPaused(bool nextPaused) external onlyRole(QuartzTypes.GUARDIAN_ROLE) {
        paused = nextPaused;
        emit PauseStatusUpdated(nextPaused);
    }

    function requireRole(bytes32 role, address account) external view {
        if (!hasRole(role, account)) revert QuartzErrors.Unauthorized(role, account);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
}
