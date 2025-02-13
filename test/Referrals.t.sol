// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./TestImports.t.sol";

contract InviteTests is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        reinitStp();
    }

    function testSetInviteBps() public {
        vm.startPrank(creator);

        vm.expectEmit(true, true, false, true, address(stp));
        emit InviteLib.InviteBpsSet(501);
        stp.setInviteBps(501);
        assertEq(stp.inviteBps(), 501);

        vm.stopPrank();

        // Attempt to set with unauthorized account
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlled.NotAuthorized.selector)
        );
        stp.setInviteBps(500);

        // Attempt to set with invalid BPS
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.setInviteBps(10001);
    }

    function testInviterCanChangeAddress() public {
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);

        // Alice now has inviter token id ID 1 (her subscription token ID)
        // She can give it to Bob
        stp.updateInviter(1, bob);

        vm.stopPrank();
    }

    function testInviteTokenId() public {
        uint256 pricePerPeriod = 0.001 ether;
        uint16 rewardBasisPoints = 1000;
        uint256 aliceTokenId = 1;

        tierParams.pricePerPeriod = pricePerPeriod;
        tierParams.initialMintPrice = 0;
        tierParams.rewardBasisPoints = rewardBasisPoints;
        stp = reinitStp();

        // Alice mints, which creates tokenId 1 & inviter token id 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's inviter token id
        assertEq(stp.inviter(aliceTokenId), alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.inviteBps()) / MAX_BPS) *
            stp.curveDetail(0).currentMultiplier;

        // Sub created for Bob using Alice's inviter token id.
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviterId: aliceTokenId,
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease
        );
    }

    function testLifetimeInvites() public {
        uint256 pricePerPeriod = 0.0025 ether;
        uint16 rewardBasisPoints = 420;
        uint256 aliceTokenId = 1;

        tierParams.pricePerPeriod = pricePerPeriod;
        tierParams.initialMintPrice = 0;
        tierParams.rewardBasisPoints = rewardBasisPoints;
        stp = reinitStp();

        // Alice mints, which creates tokenId 1 & inviter token id 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's inviter token id
        assertEq(stp.inviter(aliceTokenId), alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.inviteBps()) / MAX_BPS) *
            stp.curveDetail(0).currentMultiplier;

        // Bob use's Alices sub tokenId as inviter token id, which
        // makes her the lifetime inviter for his subscription
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviterId: aliceTokenId, // Alice's sub tokenId & inviter token id
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease
        );

        // Bob tries to mint with a different inviter token id, but it should fail
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.InvalidInviterId.selector)
        );
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviterId: aliceTokenId + 1, // Different inviter token id
                purchaseValue: pricePerPeriod
            })
        );

        // Bob mints with no inviter token id, which should automatically use Alice as the inviter
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviterId: 0, // No inviter token id
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 2
        );

        // Bob can provide Alice's inviter token id
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviterId: aliceTokenId,
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 3
        );
    }
}
