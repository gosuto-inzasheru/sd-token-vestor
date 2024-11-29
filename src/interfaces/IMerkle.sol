// SPDX-License-Identifier: GPL 3.0
pragma solidity 0.8.19;

interface IMerkle {
    function claim(address token, uint256 index, address account, uint256 amount, bytes32[] calldata proof) external;
    function isClaimed(address token, uint256 index) external view returns (bool);
    function merkleRoot(address token) external view returns (bytes32);
}
