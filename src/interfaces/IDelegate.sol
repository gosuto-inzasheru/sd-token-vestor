// SPDX-License-Identifier: GPL 3.0
pragma solidity 0.8.19;

interface IDelegate {
    function delegation(address user, bytes32 space) external view returns (address);
    function setDelegate(bytes32 space, address delegatee) external;
    function clearDelegate(bytes32 space) external;
}
