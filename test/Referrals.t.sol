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

    function testCreateAndDestroyInvite() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit InviteLib.InviteSet(code);
        stp.createCustomInviteCode(code, 500, false, address(1));
        assertEq(stp.inviteDetail(code).basisPoints, 500);
        vm.expectEmit(true, true, false, true, address(stp));
        emit InviteLib.InviteDestroyed(code);
        stp.updateInviteCode(code, 0, address(1));
        assertEq(stp.inviteDetail(code).basisPoints, 0);
    }

    function testCreateInviteInvalidBps() public prank(creator) {
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.createCustomInviteCode(
            MIN_CUSTOM_REFERRAL_CODE,
            11_000,
            false,
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.createCustomInviteCode(
            MIN_CUSTOM_REFERRAL_CODE + 1,
            5001,
            false,
            address(0)
        );
    }

    function testInvalidInviteCodes() public {
        // Test creating a invite code that's in the reserved range
        vm.startPrank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.InvalidInviteCode.selector)
        );
        stp.createCustomInviteCode(
            MIN_CUSTOM_REFERRAL_CODE - 1,
            500,
            false,
            address(0)
        );
        vm.stopPrank();

        // Test minting with a invite code that doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.NonExistantInviteCode.selector)
        );
        stp.mintAdvanced{value: 0.001 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: 123,
                purchaseValue: 0.001 ether
            })
        );

        // Test updating a invite code that doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.NonExistantInviteCode.selector)
        );
        stp.updateInviteCode(MIN_CUSTOM_REFERRAL_CODE, 500, address(0));
    }

    function testPermanentInviteCode() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit InviteLib.InviteSet(code);
        stp.createCustomInviteCode(code, 500, true, address(123));

        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.InviteLocked.selector)
        );
        stp.updateInviteCode(code, 500, address(321));
    }

    function testSetDefaultInviteBps() public {
        vm.startPrank(creator);

        vm.expectEmit(true, true, false, true, address(stp));
        emit InviteLib.DefaultInviteBpsSet(501);
        stp.setDefaultInviteBps(501);
        assertEq(stp.defaultInviteBps(), 501);

        vm.stopPrank();

        // Attempt to set with unauthorized account
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlled.NotAuthorized.selector)
        );
        stp.setDefaultInviteBps(500);

        // Attempt to set with invalid BPS
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.setDefaultInviteBps(10001);
    }

    function testInvalidBpsOfDefaultInviteId() public {
        // Alice mints, which creates tokenId 1 & invite code 1
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);

        uint16 invalidBps = stp.defaultInviteBps() + 1;

        // Alice attempts to update her invite code with BPS above defaultBps
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.updateInviteCode(1, invalidBps, alice);
        vm.stopPrank();
    }

    function testInviterCanChangeAddress() public {
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);

        // Alice now has invite code ID 1 (her subscription token ID)
        // She can give it to Bob
        stp.updateInviteCode(1, 500, bob);

        vm.stopPrank();
    }

    function testInvalidInviter() public {
        vm.startPrank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.InvalidInviter.selector)
        );
        stp.createCustomInviteCode(
            MIN_CUSTOM_REFERRAL_CODE,
            500,
            false,
            address(0)
        );
    }

    function testDefaultInviteTokenId() public {
        uint256 pricePerPeriod = 0.001 ether;
        uint16 rewardBasisPoints = 1000;
        uint256 aliceTokenId = 1;

        tierParams.pricePerPeriod = pricePerPeriod;
        tierParams.initialMintPrice = 0;
        tierParams.rewardBasisPoints = rewardBasisPoints;
        stp = reinitStp();

        // Alice mints, which creates tokenId 1 & invite code 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's invite code
        assertEq(stp.inviteDetail(aliceTokenId).inviter, alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.inviteDetail(aliceTokenId).basisPoints) / MAX_BPS) *
            stp.curveDetail(0).currentMultiplier;

        // Sub created for Bob using Alice's invite code.
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: aliceTokenId,
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

        // Alice mints, which creates tokenId 1 & invite code 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's invite code
        assertEq(stp.inviteDetail(1).inviter, alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.inviteDetail(aliceTokenId).basisPoints) / MAX_BPS) *
            stp.curveDetail(0).currentMultiplier;

        // Bob use's Alices sub tokenId as invite code, which
        // makes her the lifetime inviter for his subscription
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: 1, // Alice's sub tokenId & invite code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease
        );

        // Bob tries to mint with a different invite code, but it should fail
        vm.expectRevert(
            abi.encodeWithSelector(InviteLib.InvalidInviteCode.selector)
        );
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: 2, // Different invite code
                purchaseValue: pricePerPeriod
            })
        );

        // Bob mints with no invite code, which should automatically use Alice as the inviter
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: 0, // No invite code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 2
        );

        // Bob can provide Alice's invite code
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                inviteCode: 1, // Alice's sub tokenId & invite code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 3
        );
    }
}
