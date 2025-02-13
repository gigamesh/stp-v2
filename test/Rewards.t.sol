// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./TestImports.t.sol";

contract RewardsTest is BaseTest {
    function setUp() public {
        tierParams.periodDurationSeconds = 30 days;
        tierParams.pricePerPeriod = 0.001 ether;
        tierParams.initialMintPrice = 0.1 ether;
        tierParams.rewardCurveId = 0;
        tierParams.rewardBasisPoints = 1000; // 10%
        stp = reinitStp();

        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(charlie, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
    }

    function testCurve() public prank(creator) {
        stp.createRewardCurve(
            CurveParams({
                numPeriods: 6,
                periodSeconds: 86_400,
                startTimestamp: 0,
                minMultiplier: 0,
                decayRate: 50
            })
        );
        assertEq(stp.curveDetail(1).numPeriods, 6);
        assertEq(stp.contractDetail().numCurves, 2);
    }

    function testRewardTransfer() public {
        uint256 purchaseAmount = 0.101 ether;

        mint(alice, purchaseAmount);

        uint256 inviterRewards = (((purchaseAmount *
            tierParams.rewardBasisPoints) / MAX_BPS) * stp.inviteBps()) /
            MAX_BPS;

        uint256 expectedContractRewards = 0.0101 ether;

        assertEq(stp.contractDetail().rewardBalance, expectedContractRewards);
        stp.transferRewardsFor(alice);

        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            inviterRewards,
            1
        );
    }

    function testYield() public {
        mint(alice, 0.101 ether);
        stp.yieldRewards{value: 1 ether}(1 ether);
        assertEq(stp.contractDetail().rewardBalance, 1.0101 ether);
    }

    function testIssue() public {
        vm.expectRevert(AccessControlled.NotAuthorized.selector);
        stp.issueRewardShares(alice, 100);

        vm.startPrank(creator);
        stp.issueRewardShares(alice, 100);
        assertEq(stp.contractDetail().rewardShares, 100);
        vm.stopPrank();
    }

    function testSlashingDisabled() public {
        rewardParams.slashable = false;
        stp = reinitStp();

        mint(alice, 0.101 ether);
        vm.expectRevert(STPV2.NotSlashable.selector);
        stp.slash(alice);

        vm.warp(block.timestamp + 60 days); // past the grace period
        vm.expectRevert(STPV2.NotSlashable.selector);
        stp.slash(alice);
    }

    function testSlashing() public {
        rewardParams.slashable = true;
        rewardParams.slashGracePeriod = 7 days;
        stp = reinitStp();

        mint(alice, 0.101 ether);
        vm.expectRevert(STPV2.NotSlashable.selector);
        stp.slash(alice);

        vm.warp(block.timestamp + 60 days); // past the grace period
        stp.slash(alice);
        assertEq(stp.contractDetail().rewardShares, 0);
    }

    // Holder is slashed, but the transfer fails, so the creator is credited
    function testSlashingBadContract() public {
        rewardParams.slashable = true;
        rewardParams.slashGracePeriod = 0;
        stp = reinitStp();

        vm.startPrank(creator);
        stp.issueRewardShares(address(this), 100_000);
        stp.yieldRewards{value: 1 ether}(1 ether);
        assertEq(0, stp.contractDetail().creatorBalance);
        assertEq(1 ether, stp.contractDetail().rewardBalance);

        vm.expectEmit(true, true, false, true, address(stp));
        emit STPV2.SlashTransferFallback(address(this), 1 ether);
        stp.slash(address(this));
        assertEq(1 ether, stp.contractDetail().creatorBalance);
        assertEq(0, stp.contractDetail().rewardBalance);
        vm.stopPrank();
    }

    function rbalance(address account) internal view returns (uint256) {
        return stp.subscriptionOf(account).rewardBalance;
    }

    function rshares(address account) internal view returns (uint256) {
        return stp.subscriptionOf(account).rewardShares;
    }

    function testOrderingNoBurn() public {
        uint256 purchaseAmount = 0.101 ether;
        uint256 rewardAllocation = (purchaseAmount *
            tierParams.rewardBasisPoints) / MAX_BPS;

        uint256 inviterRewards = (rewardAllocation * stp.inviteBps()) / MAX_BPS;

        uint256 rewardsSansInviter = rewardAllocation - inviterRewards;

        mint(alice, purchaseAmount);
        assertApproxEqAbs(rbalance(alice), rewardsSansInviter, 1);

        mint(bob, purchaseAmount);
        assertApproxEqAbs(rbalance(bob), rewardsSansInviter / 2, 1);

        mint(charlie, purchaseAmount);
        assertApproxEqAbs(rbalance(charlie), rewardsSansInviter / 3, 1);
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            rewardAllocation * 3,
            1
        );

        // Doug should have no balance until more funds are allocated
        vm.startPrank(creator);
        stp.issueRewardShares(doug, rshares(charlie));
        vm.stopPrank();

        assertApproxEqAbs(rbalance(doug), 0, 1);
        assertApproxEqAbs(
            rbalance(alice) +
                rbalance(bob) +
                rbalance(charlie) +
                rbalance(doug),
            rewardsSansInviter * 3,
            3
        );
        assertEq(
            rshares(alice) + rshares(bob) + rshares(charlie) + rshares(doug),
            stp.contractDetail().rewardShares
        );

        stp.transferRewardsFor(alice);
        stp.transferRewardsFor(bob);
        stp.transferRewardsFor(charlie);

        // Some eth dust due to precision loss
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            // Inviter rewards retained by contract
            inviterRewards * 3,
            3
        );
    }

    function testOrderingBurn() public {
        uint256 purchaseAmount = 0.101 ether;

        mint(alice, 0.101 ether);
        mint(bob, 0.101 ether);
        mint(charlie, 0.101 ether);
        vm.startPrank(creator);
        stp.issueRewardShares(doug, rshares(charlie));
        vm.stopPrank();

        // burn all and check balances
        vm.warp(block.timestamp + 60 days);

        uint256 aliceBalance = alice.balance + rbalance(alice);
        uint256 bobBalance = rbalance(bob);
        uint256 charlieBalance = rbalance(charlie);

        // The contract takes inviter rewards if no inviter specified when minting
        uint256 inviterRewards = (((purchaseAmount *
            tierParams.rewardBasisPoints) / MAX_BPS) * stp.inviteBps()) /
            MAX_BPS;
        uint256 contractRetainedRewards = inviterRewards * 3;

        stp.slash(alice);
        assertEq(alice.balance, aliceBalance);

        assertEq(rbalance(bob), bobBalance);
        assertEq(rbalance(charlie), charlieBalance);
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            bobBalance + charlieBalance + contractRetainedRewards,
            3
        );

        stp.slash(bob);
        stp.slash(charlie);
        stp.slash(doug);

        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            contractRetainedRewards,
            3
        );
        assertEq(stp.contractDetail().rewardShares, 0);

        uint256 donation = 1 ether;

        vm.startPrank(creator);
        stp.issueRewardShares(doug, 10_000);
        stp.yieldRewards{value: donation}(donation);
        vm.stopPrank();

        // large allocation to doug
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            donation + contractRetainedRewards,
            3
        );

        // Doug gets all of it since his shares are 100% (10,000 bps)
        assertApproxEqAbs(rbalance(doug), donation, 3);

        stp.slash(doug);
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            contractRetainedRewards,
            3
        );

        vm.startPrank(creator);
        stp.issueRewardShares(doug, 10_000);
        stp.yieldRewards{value: 1 ether}(1 ether);
        stp.issueRewardShares(alice, 30_000); // 25% of shares
        vm.stopPrank();

        assertApproxEqAbs(rbalance(alice), 0, 3);
        assertApproxEqAbs(rbalance(doug), (1 ether), 3);

        stp.yieldRewards{value: 1 ether}(1 ether);
        assertApproxEqAbs(rbalance(doug) + rbalance(alice), (2 ether), 3);
        assertApproxEqAbs(rbalance(alice), (0.75 ether), 3);

        stp.slash(doug);
        assertApproxEqAbs(rbalance(alice), (0.75 ether), 3);
        assertEq(rbalance(doug), 0);
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance,
            (0.75 ether) + contractRetainedRewards,
            3
        );
        assertEq(
            stp.contractDetail().rewardBalance +
                stp.contractDetail().creatorBalance,
            address(stp).balance
        );
        assertApproxEqAbs(
            stp.contractDetail().rewardBalance +
                stp.contractDetail().creatorBalance,
            (0.75 ether) +
                (0.303 ether) -
                (0.0303 ether) +
                contractRetainedRewards,
            3
        );
    }
}
