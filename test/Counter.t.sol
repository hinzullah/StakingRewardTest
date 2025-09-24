// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/Staking.sol";
import {MockERC20} from "test/MockERC20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(
            address(stakingToken),
            address(rewardToken)
        );
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(
            address(staking.stakingToken()),
            address(stakingToken),
            "Wrong staking token address"
        );
        assertEq(
            address(staking.rewardsToken()),
            address(rewardToken),
            "Wrong reward token address"
        );

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(
            staking.totalSupply(),
            _totalSupplyBeforeStaking + 5e18,
            "totalsupply didnt update correctly"
        );
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(
            staking.balanceOf(bob),
            userStakebefore - 2e18,
            "Balance didnt update correctly"
        );
        assertLt(
            staking.totalSupply(),
            totalSupplyBefore,
            "total supply didnt update correctly"
        );
    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(
            staking.finishAt(),
            uint256(block.timestamp) + uint256(1 weeks)
        );
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    }

    function test_userEarnsRewardsAfterDuration() public {
        // Bob stakes
        deal(address(stakingToken), bob, 100 ether);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(100 ether);
        vm.stopPrank();

        // Fund rewards & start reward distribution
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.setRewardsDuration(1000);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward in time
        vm.warp(block.timestamp + 500);

        // Bob claims rewards
        vm.startPrank(bob);
        uint256 before = rewardToken.balanceOf(bob);
        staking.getReward();
        uint256 afterBal = rewardToken.balanceOf(bob);
        vm.stopPrank();

        assertGt(afterBal, before, "Bob did not get rewards");
        assertEq(staking.rewards(bob), 0, "Rewards not reset after claim");
    }

    function test_multipleUsersEarnRewardsFairly() public {
        // Give tokens
        deal(address(stakingToken), bob, 100 ether);
        deal(address(stakingToken), dso, 100 ether);

        // Both stake
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(100 ether);
        vm.stopPrank();

        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(100 ether);
        vm.stopPrank();

        // Owner funds rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.setRewardsDuration(1000);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Move forward
        vm.warp(block.timestamp + 1000);

        // Both claim
        vm.prank(bob);
        staking.getReward();
        vm.prank(dso);
        staking.getReward();

        uint256 bobRewards = rewardToken.balanceOf(bob);
        uint256 dsoRewards = rewardToken.balanceOf(dso);

        assertApproxEqAbs(
            bobRewards,
            dsoRewards,
            1e12,
            "Rewards not split fairly between Bob & Dso"
        );
    }
    function test_lastTimeRewardApplicable() public {
        // Initially finishAt = 0
        assertEq(staking.lastTimeRewardApplicable(), 0);

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 100 ether);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        uint256 nowTime = block.timestamp;
        assertEq(staking.lastTimeRewardApplicable(), nowTime);

        // Warp past finishAt
        vm.warp(nowTime + 2000);
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt());
    }

    function test_rewardPerToken_updatesCorrectly() public {
        // Setup Bob’s stake
        deal(address(stakingToken), bob, 100 ether);
        vm.startPrank(bob);
        stakingToken.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 100 ether);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        uint256 rptBefore = staking.rewardPerToken();
        vm.warp(block.timestamp + 500);
        uint256 rptAfter = staking.rewardPerToken();
        assertGt(rptAfter, rptBefore, "Reward per token should increase");
    }

    function test_earned_functionMatchesExpected() public {
        // Bob stakes
        deal(address(stakingToken), bob, 100 ether);
        vm.startPrank(bob);
        stakingToken.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 100 ether);
        rewardToken.transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Warp forward
        vm.warp(block.timestamp + 500);

        uint256 expected = staking.earned(bob);
        assertGt(expected, 0, "Earned should be greater than 0");
    }
}
