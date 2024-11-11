// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OllieCoin.sol";
import "../src/RewardCoin.sol";

contract MockBridge {
    function transferTokens(IERC20 token, address from, address to, uint256 amount) external {
        token.transferFrom(from, to, amount);
    }
}

contract OllieCoinTest is Test {
    OllieCoin public ollieCoin;
    RewardCoin public rewardCoin;
    MockBridge public bridge;

    address public ollie = address(0x4);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    function setUp() public {
        // Label addresses for better trace output
        vm.label(ollie, "Ollie");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");

        bridge = new MockBridge();
        vm.label(address(bridge), "Bridge");
    }

    // Main test

    function testDistributions() public {
        uint256 startTime = 1 days;
        vm.warp(startTime); // Start at day 1
        console.log("\n=== Starting Distribution Test at timestamp:", startTime);

        // Setup - Ollie creates both tokens
        vm.startPrank(ollie);
        rewardCoin = new RewardCoin();
        ollieCoin = new OllieCoin("OllieCoin", "OLLIE", ollie);

        // Mint initial OllieCoins
        ollieCoin.mint(user1, 100);
        ollieCoin.mint(user2, 100);
        ollieCoin.mint(user3, 100);

        console.log("\n=== Initial Token Distribution ===");
        console.log("User1 OllieCoin balance:", ollieCoin.balanceOf(user1));
        console.log("User2 OllieCoin balance:", ollieCoin.balanceOf(user2));
        console.log("User3 OllieCoin balance:", ollieCoin.balanceOf(user3));

        vm.stopPrank();

        vm.startPrank(ollie);
        // Mint RewardCoins to Ollie for distribution
        rewardCoin.mint(ollie, 900);
        rewardCoin.approve(address(ollieCoin), 900 * 1e18);

        // Distribution 1
        vm.warp(startTime + 30 days);
        console.log("\n=== Distribution 1 at timestamp:", startTime + 30 days);
        ollieCoin.distribute(rewardCoin, 300 * 1e18);
        console.log("Distributed 300 RewardCoins");
        vm.stopPrank();

        // user 1 transfers to user 2
        vm.startPrank(user1);
        console.log("\n=== User1 transfers 100 OllieCoins to User2 ===");
        ollieCoin.transfer(user2, 100);
        vm.stopPrank();

        console.log("After transfer - User1 balance:", ollieCoin.balanceOf(user1));
        console.log("After transfer - User2 balance:", ollieCoin.balanceOf(user2));

        // add 1 second to make sure the next claim is in the next day
        vm.warp(startTime + 30 days + 1 seconds);

        // Distribution 2
        vm.startPrank(ollie);
        vm.warp(startTime + 60 days);
        console.log("\n=== Distribution 2 at timestamp:", startTime + 60 days);
        ollieCoin.distribute(rewardCoin, 300 * 1e18);
        console.log("Distributed 300 RewardCoins");
        vm.stopPrank();

        // User 2 transfers to User 3 and claims
        vm.startPrank(user2);
        console.log("\n=== User2 transfers 200 OllieCoins to User3 and claims ===");
        ollieCoin.transfer(user3, 200);
        console.log("Before claim - User2 pending rewards:", ollieCoin.getPendingRewards(user2));
        ollieCoin.claim();
        console.log("After claim - User2 RewardCoin balance:", rewardCoin.balanceOf(user2));
        vm.stopPrank();

        // User 1 claims
        vm.startPrank(user1);
        console.log("\n=== User1 claims ===");
        console.log("Before claim - User1 pending rewards:", ollieCoin.getPendingRewards(user1));
        ollieCoin.claim();
        console.log("After claim - User1 RewardCoin balance:", rewardCoin.balanceOf(user1));
        vm.stopPrank();

        // Distribution 3
        vm.startPrank(ollie);
        vm.warp(startTime + 90 days);
        console.log("\n=== Distribution 3 at timestamp:", startTime + 90 days);
        ollieCoin.distribute(rewardCoin, 300 * 1e18);
        console.log("Distributed 300 RewardCoins");
        vm.stopPrank();

        // Final claims
        console.log("\n=== Final Claims ===");

        vm.startPrank(user1);
        console.log("User1 pending rewards before final claim:", ollieCoin.getPendingRewards(user1));
        ollieCoin.claim();
        console.log("User1 final RewardCoin balance:", rewardCoin.balanceOf(user1));
        vm.stopPrank();

        vm.startPrank(user2);
        console.log("User2 pending rewards before final claim:", ollieCoin.getPendingRewards(user2));
        ollieCoin.claim();
        console.log("User2 final RewardCoin balance:", rewardCoin.balanceOf(user2));
        vm.stopPrank();

        vm.startPrank(user3);
        console.log("User3 pending rewards before final claim:", ollieCoin.getPendingRewards(user3));
        ollieCoin.claim();
        console.log("User3 final RewardCoin balance:", rewardCoin.balanceOf(user3));
        vm.stopPrank();

        console.log("\n=== Final Token Balances ===");
        console.log("User1 OllieCoin:", ollieCoin.balanceOf(user1));
        console.log("User2 OllieCoin:", ollieCoin.balanceOf(user2));
        console.log("User3 OllieCoin:", ollieCoin.balanceOf(user3));
        console.log("User1 RewardCoin:", rewardCoin.balanceOf(user1));
        console.log("User2 RewardCoin:", rewardCoin.balanceOf(user2));
        console.log("User3 RewardCoin:", rewardCoin.balanceOf(user3));

        // Final assertions remain the same
        assertApproxEqRel(rewardCoin.balanceOf(user1), 100 * 1e18, 0.01e18, "User 1 should have about 100 balance");
        assertApproxEqRel(rewardCoin.balanceOf(user2), 300 * 1e18, 0.01e18, "User 2 should have about 300 balance");
        assertApproxEqRel(rewardCoin.balanceOf(user3), 500 * 1e18, 0.01e18, "User 3 should have about 500 balance");
        assertEq(ollieCoin.balanceOf(user1), 0, "User 1 should have 0 balance");
        assertEq(ollieCoin.balanceOf(user2), 0, "User 2 should have 0 balance");
        assertEq(ollieCoin.balanceOf(user3), 300, "User 3 should have 300 balance");
    }

    // Delegation tests

    function testRewardWeightPreservation() public {
        // Setup initial state
        uint256 startTime = 1 days;
        vm.warp(startTime);
        vm.startPrank(ollie);
        rewardCoin = new RewardCoin();
        ollieCoin = new OllieCoin("OllieCoin", "OLLIE", ollie);
        // Mint initial tokens to user1
        ollieCoin.mint(user1, 100);
        vm.stopPrank();
        // Move time forward and.delegateRewards
        vm.warp(startTime + 1 hours);
        vm.prank(user1);
        ollieCoin.delegateRewards(user1);
        // Move time forward for reward weight check
        vm.warp(startTime + 2 hours);

        // Initial checks
        assertEq(ollieCoin.balanceOf(user1), 100, "Initial balance should be 100");
        assertEq(
            ollieCoin.getPastBalance(user1, uint48(startTime + 1 hours)), 100, "Initial reward weight should be 100"
        );
        // User1 approves bridge and sets reward weight preservation
        vm.startPrank(user1);
        ollieCoin.approve(address(bridge), 100);
        ollieCoin.setRewardWeightPreservation(address(bridge), true);
        vm.stopPrank();
        // Move time forward before bridge transfer
        vm.warp(startTime + 3 hours);
        // Bridge transfers tokens
        vm.prank(address(bridge));
        bridge.transferTokens(ollieCoin, user1, user2, 50);
        // Move time forward for final checks
        vm.warp(startTime + 4 hours);
        // Check balances and reward weight
        assertEq(ollieCoin.balanceOf(user1), 50, "User1 balance should be 50");
        assertEq(ollieCoin.balanceOf(user2), 50, "User2 balance should be 50");
        assertEq(
            ollieCoin.getPastBalance(user1, uint48(startTime + 3 hours)), 100, "User1 reward weight should remain 100"
        );
        assertEq(ollieCoin.getPastBalance(user2, uint48(startTime + 3 hours)), 0, "User2 should have no reward weight");
    }

    function testRegularTransferVsPreservedTransfer() public {
        uint256 startTime = 1 days;
        vm.warp(startTime);
        // Setup
        vm.startPrank(ollie);
        rewardCoin = new RewardCoin();
        ollieCoin = new OllieCoin("OllieCoin", "OLLIE", ollie);
        ollieCoin.mint(user1, 200);
        vm.stopPrank();

        // Move time forward and delegate rewards for user1
        vm.warp(startTime + 1 hours);
        vm.prank(user1);
        ollieCoin.delegateRewards(user1);
        // Move time forward before transfers
        vm.warp(startTime + 2 hours);
        // User1 sets up different transfers
        vm.startPrank(user1);
        ollieCoin.approve(address(bridge), 100);
        ollieCoin.setRewardWeightPreservation(address(bridge), true);

        // Regular transfer to user2
        ollieCoin.transfer(user2, 100);
        vm.stopPrank();

        // User2.delegateRewardss to themselves
        vm.prank(user2);
        ollieCoin.delegateRewards(user2);

        // Preserved transfer via bridge to user3
        vm.prank(user1);
        bridge.transferTokens(ollieCoin, user1, user3, 100);
        // Move time forward for checks
        vm.warp(startTime + 3 hours);
        // Check states
        assertEq(
            ollieCoin.getPastBalance(user1, uint48(startTime + 2 hours)),
            100,
            "User1 should keep reward weight from preserved transfer"
        );
        assertEq(
            ollieCoin.getPastBalance(user2, uint48(startTime + 2 hours)),
            100,
            "User2 should have reward weight from regular transfer"
        );
        assertEq(
            ollieCoin.getPastBalance(user3, uint48(startTime + 2 hours)),
            0,
            "User3 should have no reward weight from preserved transfer"
        );
    }

    function testToggleRewardWeightPreservation() public {
        uint256 startTime = 1 days;
        vm.warp(startTime); // Day 1
        // Setup
        vm.startPrank(ollie);
        rewardCoin = new RewardCoin();
        ollieCoin = new OllieCoin("OllieCoin", "OLLIE", ollie);
        ollieCoin.mint(user1, 100);
        vm.stopPrank();
        // Move to Day 2
        vm.warp(startTime + 1 days);
        vm.prank(user1);
        ollieCoin.delegateRewards(user1);
        // Move to Day 3
        vm.warp(startTime + 2 days);
        vm.startPrank(user1);
        ollieCoin.approve(address(bridge), type(uint256).max);
        ollieCoin.setRewardWeightPreservation(address(bridge), true);
        // First transfer with preservation ON
        bridge.transferTokens(ollieCoin, user1, user2, 50);
        vm.warp(startTime + 2 days + 1 hours);
        // Turn off preservation
        ollieCoin.setRewardWeightPreservation(address(bridge), false);

        // Second transfer (no preservation)
        bridge.transferTokens(ollieCoin, user1, user2, 50);
        vm.warp(startTime + 2 days + 2 hours);

        // Final assertions
        assertEq(ollieCoin.balanceOf(user1), 0, "User1 should have 0 balance");
        assertEq(ollieCoin.balanceOf(user2), 100, "User2 should have full balance");
        assertEq(
            ollieCoin.getPastBalance(user1, uint48(startTime + 2 days + 1 hours)),
            50, // Should keep the preserved rewards from first transfer
            "User1 should keep preserved reward weight from first transfer"
        );
        vm.stopPrank();
    }
}
