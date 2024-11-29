// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/interfaces/IVester.sol";
import "src/interfaces/IMerkle.sol";
import "src/interfaces/IDelegate.sol";
import "src/interfaces/ILiquidityGauge.sol";

/// @title Vester contract
/// @notice Each Beneficiary has a personal vesting contract deployed.
contract Vester is Initializable, Pausable, IVester {
    using SafeERC20 for ERC20;

    //////////////////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////////

    /// @notice Factory address.
    address public FACTORY;

    /// @notice Manager role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Ragequit role.
    bytes32 public constant RAGEQUIT_ROLE = keccak256("RAGEQUIT_ROLE");

    /// @notice Beneficiary role.
    bytes32 public constant BENEFICIARY_ROLE = keccak256("BENEFICIARY_ROLE");

    /// @notice Default vesting period.
    uint256 public constant DEFAULT_VESTING_PERIOD = 365 days;

    /// @notice Stake DAO Delegation address.
    address public constant DELEGATION = address(0x52ea58f4FC3CEd48fa18E909226c1f8A0EF887DC);

    /// @notice Snapshot Delegation registry address.
    address public constant DELEGATION_REGISTRY = address(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);

    /// @notice Delegation space.
    bytes32 public immutable DELEGATION_SPACE;

    /// @notice Stake DAO Token Gauge address. Token vested.
    ERC20 public immutable SD_TOKEN_GAUGE;

    /// @notice Voting rewards merkle stash address.
    address public immutable VOTING_REWARDS_MERKLE_STASH;

    //////////////////////////////////////////////////////////////////
    /// --- STORAGE
    //////////////////////////////////////////////////////////////////

    /// @notice Beneficiary address.
    address public beneficiary;

    /// @notice Vesting nonce.
    uint256 internal vestingNonce;

    /// @notice Mapping for vesting positions.
    // Nonce -> VestingPosition
    mapping(uint256 => VestingPosition) internal vestingPositions;

    //////////////////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////////////////

    /// @notice Emitted when the beneficiary is changed.
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    /// @notice Emitted when a vesting position is created.
    event VestingPositionCreated(uint256 indexed nonce, uint256 amount, uint256 vestingEnds);

    /// @notice Emitted when a vesting position is claimed.
    event Claimed(uint256 indexed nonce, uint256 amount);

    /// @notice Emitted when the contract is ragequit.
    event Ragequit(address indexed to);

    /// @notice Emitted when a token is swept.
    event Sweep(address indexed token, uint256 amount, address indexed to);

    /// @notice Error emitted when the ragequit address is the zero address.
    error InvalidAddress();

    /// @notice Error emitted when a vesting position has already been claimed.
    error AlreadyClaimed();

    /// @notice Error emitted when a vesting position has not yet vested.
    error NotVestedYet();

    /// @notice Error emitted when a protected token is swept.
    error ProtectedToken();

    /// @notice Error emitted when the token has no voting rewards.
    error NoVotingRewards();

    /// @notice Error emitted when the caller is not authorized.
    error Unauthorized(bytes32 role);

    modifier onlyRole(bytes32 role) {
        if (!IAccessControl(FACTORY).hasRole(role, msg.sender)) {
            revert Unauthorized(role);
        }
        _;
    }

    modifier onlyBeneficiary() {
        if (beneficiary != msg.sender) {
            revert Unauthorized(BENEFICIARY_ROLE);
        }
        _;
    }

    constructor(bytes32 _delegationSpace, address _sdTokenGauge, address _votingRewardsMerkleStash) {
        // Disable initializers for the implementation contract
        _disableInitializers();

        DELEGATION_SPACE = _delegationSpace;
        SD_TOKEN_GAUGE = ERC20(_sdTokenGauge);
        VOTING_REWARDS_MERKLE_STASH = _votingRewardsMerkleStash;
    }

    /// @notice Contract initializer
    /// @param _beneficiary Address of the beneficiary that will be able to claim tokens
    function initialize(address _beneficiary) public initializer {
        /// Initialize factory address.
        FACTORY = msg.sender;

        /// Initialize beneficiary.
        beneficiary = _beneficiary;

        /// Delegate to Stake DAO delegation.
        IDelegate(DELEGATION_REGISTRY).setDelegate(DELEGATION_SPACE, DELEGATION);
    }

    //////////////////////////////////////////////////////////////////
    //                       External functions                     //
    //////////////////////////////////////////////////////////////////
    /// @notice Get current vesting nonce. This nonce represents future vesting position nonce
    /// @dev If needed to check current existing nonce, subtract 1 from this value
    function getVestingNonce() external view returns (uint256) {
        return vestingNonce;
    }

    /// @notice Get vesting position by nonce
    /// @param _nonce Nonce of the vesting position
    function getVestingPosition(uint256 _nonce) external view returns (VestingPosition memory) {
        return vestingPositions[_nonce];
    }

    /// @notice Deposit logic
    /// @param _amount Amount of tokens to deposit
    /// @param _vestingPeriod Vesting period in seconds
    function deposit(uint256 _amount, uint256 _vestingPeriod) external onlyRole(MANAGER_ROLE) whenNotPaused {
        _deposit(_amount, _vestingPeriod);
    }

    /// @notice Sweep any ERC20 token except vested tokens.
    /// @param _token Address of the token to sweep
    /// @param _amount Amount of tokens to sweep
    /// @param _to Address to send the tokens to
    function sweep(address _token, uint256 _amount, address _to) external onlyRole(MANAGER_ROLE) {
        if (_token == address(SD_TOKEN_GAUGE)) {
            revert ProtectedToken();
        }
        ERC20(_token).safeTransfer(_to, _amount);
        emit Sweep(_token, _amount, _to);
    }

    /// @notice Ragequit all in case of emergency
    /// @dev This function is only callable by the DAO multisig
    /// @param _to Address to send all vested tokens to.
    function ragequit(address _to) external onlyRole(RAGEQUIT_ROLE) {
        if (_to == address(0)) {
            revert InvalidAddress();
        }
        /// Claim rewards and transfer vested tokens to _to parameter.
        ILiquidityGauge(address(SD_TOKEN_GAUGE)).claim_rewards(address(this), _to);

        /// Transfer vested tokens to _to parameter.
        SD_TOKEN_GAUGE.safeTransfer(_to, SD_TOKEN_GAUGE.balanceOf(address(this)));

        /// Pause and render the contract useless
        _pause();

        /// Clear delegation.
        IDelegate(DELEGATION_REGISTRY).clearDelegate(DELEGATION_SPACE);

        emit Ragequit(_to);
    }

    //////////////////////////////////////////////////////////////////
    /// --- BENEFICIARY FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @notice Claim vesting position
    /// @param _nonce Nonce of the vesting position
    function claim(uint256 _nonce) external onlyBeneficiary whenNotPaused {
        /// Get vesting position.
        VestingPosition storage vestingPosition = vestingPositions[_nonce];

        /// Check if the vesting position has already been claimed.
        if (vestingPosition.claimed) {
            revert AlreadyClaimed();
        }

        /// Check if the vesting period has ended.
        if (block.timestamp < vestingPosition.vestingEnds) {
            revert NotVestedYet();
        }

        /// Mark vesting position as claimed.
        vestingPosition.claimed = true;

        /// Claim rewards to the beneficiary.
        ILiquidityGauge(address(SD_TOKEN_GAUGE)).claim_rewards(address(this), msg.sender);

        /// Transfer vested tokens to beneficiary.
        SD_TOKEN_GAUGE.safeTransfer(msg.sender, vestingPosition.amount);

        emit Claimed(_nonce, vestingPosition.amount);
    }

    /// @notice Function to claim rewards from the liquidity gauge.
    /// @notice Can be still claimed even if the contract is paused.
    function claimRewards() external onlyBeneficiary {
        ILiquidityGauge(address(SD_TOKEN_GAUGE)).claim_rewards(address(this), beneficiary);
    }

    /// @notice Function to claim voting rewards from the merkle stash.
    /// SD Token Gauge Holders are eligible for voting rewards that can be claimed by providing a merkle proof.
    /// @param token Address of the token to claim rewards for
    /// @param index Index of the reward in the merkle tree
    /// @param amount Amount of rewards to claim
    /// @param proofs Merkle proof to claim the rewards
    function claimVotingRewards(address token, uint256 index, uint256 amount, bytes32[] calldata proofs)
        external
        onlyBeneficiary
    {
        /// Check if the token has voting rewards.
        if (IMerkle(VOTING_REWARDS_MERKLE_STASH).merkleRoot(token) == bytes32(0) && token != address(SD_TOKEN_GAUGE)) {
            revert NoVotingRewards();
        }

        /// Check if the reward has already been claimed.
        if (!IMerkle(VOTING_REWARDS_MERKLE_STASH).isClaimed(token, index)) {
            /// Claim voting rewards.
            IMerkle(VOTING_REWARDS_MERKLE_STASH).claim(token, index, address(this), amount, proofs);
        }

        /// Transfer voting rewards to beneficiary.
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    //////////////////////////////////////////////////////////////////
    /// --- DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////////

    function _deposit(uint256 _amount, uint256 _vestingPeriod) internal {
        /// Get current nonce.
        uint256 _nonce = vestingNonce;

        /// Increment nonce.
        vestingNonce++;

        /// Calculate vesting end time.
        uint256 vestingEnds = block.timestamp + _vestingPeriod;

        /// Store vesting position.
        vestingPositions[_nonce] = VestingPosition(_amount, vestingEnds, false);

        /// Transfer tokens from sender to this contract.
        SD_TOKEN_GAUGE.safeTransferFrom(msg.sender, address(this), _amount);

        emit VestingPositionCreated(_nonce, _amount, vestingEnds);
    }

    //////////////////////////////////////////////////////////////////
    /// --- MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////////

    /// @notice Update delegation to Stake DAO delegation
    /// @param _delegate Address of the delegate
    function updateDelegation(address _delegate) external onlyRole(MANAGER_ROLE) {
        IDelegate(DELEGATION_REGISTRY).setDelegate(DELEGATION_SPACE, _delegate);
    }

    /// @notice Deposit logic but with default vesting period
    /// @param _amount Amount of tokens to deposit
    function deposit(uint256 _amount) external onlyRole(MANAGER_ROLE) whenNotPaused {
        _deposit(_amount, DEFAULT_VESTING_PERIOD);
    }

    /// @notice Set beneficiary
    /// @param _beneficiary Address of the beneficiary
    function setBeneficiary(address _beneficiary) public onlyRole(MANAGER_ROLE) {
        address oldBeneficiary = beneficiary;

        /// Set new beneficiary.
        beneficiary = _beneficiary;

        emit BeneficiaryChanged(oldBeneficiary, _beneficiary);
    }
}
