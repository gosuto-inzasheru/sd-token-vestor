// SPDX-License-Identifier: GPL 3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "src/interfaces/IFactory.sol";
import "src/interfaces/IVester.sol";

contract Factory is Ownable, IFactory, AccessControl {
    using Clones for address;

    //////////////////////////////////////////////////////////////////
    /// --- ROLES
    //////////////////////////////////////////////////////////////////

    /// @notice Manager role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Ragequit role.
    bytes32 public constant RAGEQUIT_ROLE = keccak256("RAGEQUIT_ROLE");

    //////////////////////////////////////////////////////////////////
    /// --- STORAGE
    //////////////////////////////////////////////////////////////////

    /// @notice Vester Implementation.
    address public implementation;

    /// @notice Mapping of user to vesting contracts deployed.
    mapping(address => address[]) public vestingContracts;

    //////////////////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////////////////

    /// @notice Emitted when the implementation is changed.
    event LogImplementationChanged(address indexed oldImplementation, address indexed newImplementation);

    /// @notice Emitted when a vesting contract is deployed.
    event LogVestingContractDeployed(address indexed vestingContract, address indexed owner);

    /// @notice Factory constructor
    /// @param _implementation Address of the implementation
    /// @param _owner Address of the owner
    constructor(address _implementation, address _owner) Ownable() {
        implementation = _implementation;
        _transferOwnership(_owner);

        _grantRole(MANAGER_ROLE, _owner);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /// @notice Get vesting contracts deployed for a user
    /// @param _user Address of the user
    function getVestingContracts(address _user) public view returns (address[] memory) {
        return vestingContracts[_user];
    }

    //////////////////////////////////////////////////////////////////
    /// --- OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @notice Deploy a new vesting contract
    function deployVestingContract(address _beneficiary) public onlyOwner returns (address vestingContract) {
        /// Clone implementation.
        vestingContract = implementation.clone();

        /// Initialise vesting with beneficiary.
        IVester(vestingContract).initialize(_beneficiary);

        /// Store vesting.
        vestingContracts[_beneficiary].push(vestingContract);

        emit LogVestingContractDeployed(vestingContract, _beneficiary);
    }

    /// @notice Set implementation address
    /// @param _implementation Address of the implementation
    function setImplementation(address _implementation) public onlyOwner {
        implementation = _implementation;
        emit LogImplementationChanged(implementation, _implementation);
    }
}
