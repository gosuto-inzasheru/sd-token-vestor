// SPDX-License-Identifier: GPL 3.0
pragma solidity 0.8.19;

interface IFactory {
    /// @notice Deploy a new vesting contract
    function deployVestingContract(address _beneficiary) external returns (address vestingContract);
    /// @notice Get vesting contracts deployed for a user
    function getVestingContracts(address _user) external view returns (address[] memory);
    /// @notice Set implementation address
    function setImplementation(address _implementation) external;
}
