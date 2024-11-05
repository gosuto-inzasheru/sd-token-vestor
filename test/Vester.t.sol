// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "test/Utils.sol";
import "src/Vester.sol";
import "src/Factory.sol";

/// @notice Mock contract for testing merkle claims
contract MockMerkle {
    function claim(address token, uint256, address account, uint256 amount, bytes32[] calldata) public {
        ERC20(token).transfer(account, amount);
    }
}

/// @title Vester Contract Tests
/// @notice Test suite for the Vester contract functionality
contract VesterTest is Test {
    // Constants - Protocol Addresses
    address public constant SD_DELEGATION = address(0x52ea58f4FC3CEd48fa18E909226c1f8A0EF887DC);
    address public constant DELEGATION_REGISTRY = address(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    address public constant VOTING_REWARDS_MERKLE_STASH = address(0x03E34b085C52985F6a5D27243F20C84bDdc01Db4);
    address public constant MAXIS_OPS = address(0x166f54F44F271407f24AA1BE415a730035637325);
    address public constant DAO_MSIG = address(0x10A19e7eE7d7F8a52822f6817de8ea18204F2e4f);

    // Constants - Token Addresses
    ERC20 public constant SD_BAL_GAUGE = ERC20(address(0x3E8C72655e48591d93e6dfdA16823dB0fF23d859));
    ERC20 public constant SD_BAL = ERC20(address(0xF24d8651578a55b0C119B9910759a351A3458895));
    ERC20 public constant BAL = ERC20(address(0xba100000625a3754423978a60c9317c58a424e3D));
    ERC20 public constant USDC = ERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

    // Test accounts
    Utils internal utils;
    address payable[] internal users;
    address public alice;
    address public bob;
    address public randomEOA;

    // Contracts
    Factory public factory;
    Vester public vester;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_329);

        // Setup test accounts
        utils = new Utils();
        users = utils.createUsers(5);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        randomEOA = users[2];
        vm.label(randomEOA, "randomEOA");

        // Deploy contracts
        vester = new Vester(bytes32("sdbal.eth"), address(SD_BAL_GAUGE), VOTING_REWARDS_MERKLE_STASH);
        factory = new Factory(address(vester), MAXIS_OPS);

        // Setup roles
        vm.prank(MAXIS_OPS);
        factory.grantRole(bytes32(keccak256("RAGEQUIT_ROLE")), address(DAO_MSIG));
    }

    /// -----------------------------------------------------------------------
    /// Beneficiary Management Tests
    /// -----------------------------------------------------------------------

    /// @notice Tests manager can set beneficiary
    function testSetBeneficiaryBis() public {
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        vm.prank(MAXIS_OPS);
        aliceVester.setBeneficiary(bob);

        assertEq(aliceVester.beneficiary(), bob);
    }

    /// @notice Tests unauthorized beneficiary change reverts
    function testSetBeneficiaryUnhappy() public {
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        vm.expectRevert(abi.encodeWithSelector(Vester.Unauthorized.selector, factory.MANAGER_ROLE()));
        vm.prank(alice);
        aliceVester.setBeneficiary(bob);
    }

    /// -----------------------------------------------------------------------
    /// Deposit and Claim Tests
    /// -----------------------------------------------------------------------

    /// @notice Tests successful deposit creates vesting position
    function testDepositHappy(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount);

        assertEq(aliceVester.getVestingNonce(), 1);
        assertEq(SD_BAL_GAUGE.balanceOf(address(aliceVester)), _depositAmount);

        Vester.VestingPosition memory vestingPosition = aliceVester.getVestingPosition(0);
        assertEq(vestingPosition.amount, _depositAmount);
        assertFalse(vestingPosition.claimed);
    }

    /// @notice Tests simple claim
    function testClaimHappyStandardVestingPeriod(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount);

        // Roll time to the end of the vesting period
        skip(vester.DEFAULT_VESTING_PERIOD());

        // Claim
        vm.prank(alice);
        aliceVester.claim(0);

        // Make sure the vesting position has been claimed
        Vester.VestingPosition memory vestingPosition = aliceVester.getVestingPosition(0);
        assertTrue(vestingPosition.claimed);

        // Check Alice balance now:
        assertEq(SD_BAL_GAUGE.balanceOf(address(alice)), _depositAmount);
        assertGt(BAL.balanceOf(address(alice)), 0);
        assertGt(USDC.balanceOf(address(alice)), 0);
    }

    function testClaimHappyCustomVestingPeriod(uint256 _depositAmount, uint256 _vestingPeriod) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        _vestingPeriod = bound(_vestingPeriod, 1 days, 1000 days);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount, _vestingPeriod);

        // Roll time to the end of the vesting period
        vm.warp(block.timestamp + _vestingPeriod);

        // Claim
        vm.prank(alice);
        aliceVester.claim(0);

        // Make sure the vesting position has been claimed
        Vester.VestingPosition memory vestingPosition = aliceVester.getVestingPosition(0);
        assertTrue(vestingPosition.claimed);

        // Check Alice balance now:
        assertEq(SD_BAL_GAUGE.balanceOf(address(alice)), _depositAmount);
        assertGt(BAL.balanceOf(address(alice)), 0);
        assertGt(USDC.balanceOf(address(alice)), 0);
    }

    function testMultipleClaims(uint256 _depositAmount, uint256 _positionsAmnt) public {
        _positionsAmnt = bound(_positionsAmnt, 1, 10);
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply() / _positionsAmnt);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), SD_BAL_GAUGE.totalSupply());

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), type(uint256).max);
        for (uint256 i = 0; i < _positionsAmnt; i++) {
            vm.prank(MAXIS_OPS);
            aliceVester.deposit(_depositAmount);
            // Check nonce:
            assertEq(aliceVester.getVestingNonce(), i + 1);
        }
        // Now roll time to the end of the vesting period and claim all positions
        skip(vester.DEFAULT_VESTING_PERIOD());

        for (uint256 i = 0; i < _positionsAmnt; i++) {
            vm.prank(alice);
            Vester(aliceVester).claim(i);
        }
        // Make sure Alice balance is now _depositAmount * _positionsAmnt
        assertEq(SD_BAL_GAUGE.balanceOf(address(alice)), _depositAmount * _positionsAmnt);
        assertGt(BAL.balanceOf(address(alice)), 0);
        assertGt(USDC.balanceOf(address(alice)), 0);
    }

    /// @notice Should revert when trying to claim too early
    function testClaimTooEarly(uint256 _depositAmount, uint256 _vestingPeriod) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        _vestingPeriod = bound(_vestingPeriod, 1 days, 1000 days);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount, _vestingPeriod);

        // Roll time almost to the end of the vesting period
        skip(_vestingPeriod - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vester.NotVestedYet.selector));
        aliceVester.claim(0);
    }

    function testClaimNotBeneficiary(uint256 _depositAmount, uint256 _vestingPeriod) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        _vestingPeriod = bound(_vestingPeriod, 1 days, 1000 days);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount, _vestingPeriod);

        skip(_vestingPeriod + 1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Vester.Unauthorized.selector, vester.BENEFICIARY_ROLE()));
        aliceVester.claim(0);
    }

    /// @notice Should revert when trying to claim same position twice
    function testClaimCannotClaimMulTimes(uint256 _depositAmount, uint256 _vestingPeriod) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        _vestingPeriod = bound(_vestingPeriod, 1 days, 1000 days);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount, _vestingPeriod);

        skip(_vestingPeriod + 1);

        vm.prank(alice);
        aliceVester.claim(0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vester.AlreadyClaimed.selector));
        aliceVester.claim(0);
    }

    /// -----------------------------------------------------------------------
    /// Claim Rewards Tests
    /// -----------------------------------------------------------------------

    function testClaimAuraRewards(uint256 _depositAmount, uint256 _vestingPeriod) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        _vestingPeriod = bound(_vestingPeriod, 1 days, 1000 days);
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));
        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount, _vestingPeriod);
        // Aura rewards will start pounding in immediately, so no need to warp time
        skip(1 days);

        vm.prank(alice);
        aliceVester.claimRewards();
        assertGt(BAL.balanceOf(address(alice)), 0);
        assertGt(USDC.balanceOf(address(alice)), 0);
    }

    /// -----------------------------------------------------------------------
    /// Sweep Tests
    /// -----------------------------------------------------------------------

    function testSweepHappy(uint256 _sweepAmount) public {
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        // Now give vesting contract some tokens and sweep them
        deal(address(BAL), address(aliceVester), _sweepAmount);

        // DAO msig can sweep now
        vm.prank(MAXIS_OPS);
        aliceVester.sweep(address(BAL), _sweepAmount, bob);

        assertEq(BAL.balanceOf(bob), _sweepAmount);
    }

    function testSweepUnhappyProtected(uint256 _sweepAmount) public {
        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(aliceVester), _sweepAmount);

        // DAO msig can sweep now
        vm.prank(MAXIS_OPS);
        vm.expectRevert(abi.encodeWithSelector(Vester.ProtectedToken.selector));
        aliceVester.sweep(address(SD_BAL_GAUGE), _sweepAmount, bob);

        assertEq(SD_BAL_GAUGE.balanceOf(bob), 0);
    }

    /// -----------------------------------------------------------------------
    /// Ragequit Tests
    /// -----------------------------------------------------------------------

    function testRageQuitHappy(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());
        vm.prank(MAXIS_OPS);

        Vester aliceVester = Vester(factory.deployVestingContract(alice));
        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount);

        // Roll time to the end of the vesting period to accrue BAL rewards
        vm.warp(block.timestamp + vester.DEFAULT_VESTING_PERIOD());

        // Rage quite to random EOA
        vm.prank(DAO_MSIG);
        aliceVester.ragequit(randomEOA);
        assertEq(SD_BAL_GAUGE.balanceOf(randomEOA), _depositAmount);
        assertGt(BAL.balanceOf(randomEOA), 0);

        // Make sure vester has no more st auraBAL
        assertEq(SD_BAL_GAUGE.balanceOf(address(aliceVester)), 0);
        // Make sure vester has no more BAL
        assertEq(BAL.balanceOf(address(aliceVester)), 0);
        // Make sure contract is bricked
        assertTrue(aliceVester.paused());
    }

    function testCannotRQToZeroAddr(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());

        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));

        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount);

        // Roll time to the end of the vesting period to accrue BAL rewards
        skip(vester.DEFAULT_VESTING_PERIOD());

        // Rage quite to random EOA
        vm.prank(DAO_MSIG);
        vm.expectRevert(Vester.InvalidAddress.selector);
        aliceVester.ragequit(address(0));
        assertFalse(aliceVester.paused());
    }

    function testClaimVotingRewards(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, SD_BAL_GAUGE.totalSupply());

        vm.prank(MAXIS_OPS);
        Vester aliceVester = Vester(factory.deployVestingContract(alice));
        deal(address(SD_BAL_GAUGE), address(MAXIS_OPS), _depositAmount);

        vm.prank(MAXIS_OPS);
        SD_BAL_GAUGE.approve(address(aliceVester), _depositAmount);

        vm.prank(MAXIS_OPS);
        aliceVester.deposit(_depositAmount);

        skip(1 days);

        vm.prank(alice);
        vm.expectRevert("Invalid proof.");
        aliceVester.claimVotingRewards(address(SD_BAL), 0, 1e18, new bytes32[](0));

        assertEq(SD_BAL.balanceOf(alice), 0);
        assertEq(SD_BAL.balanceOf(address(aliceVester)), 0);

        address votingRewardsMerkleStash = vester.VOTING_REWARDS_MERKLE_STASH();
        vm.mockFunction(
            votingRewardsMerkleStash,
            address(new MockMerkle()),
            abi.encodeWithSignature("claim(address,uint256,address,uint256,bytes32[])")
        );

        vm.prank(alice);
        aliceVester.claimVotingRewards(address(SD_BAL), 0, 1e18, new bytes32[](0));

        assertEq(SD_BAL.balanceOf(alice), 1e18);
        assertEq(SD_BAL.balanceOf(address(aliceVester)), 0);
    }
}