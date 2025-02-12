// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./TestImports.t.sol";

contract ReferralTests is BaseTest {
    function setUp() public {
        deal(alice, 1e19);
        deal(bob, 1e19);
        deal(creator, 1e19);
        deal(fees, 1e19);
        reinitStp();
    }

    function testCreateAndDestroyReferral() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralSet(code);
        stp.createCustomReferralCode(code, 500, false, address(1));
        assertEq(stp.referralDetail(code).basisPoints, 500);
        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralDestroyed(code);
        stp.updateReferralCode(code, 0, address(1));
        assertEq(stp.referralDetail(code).basisPoints, 0);
    }

    function testCreateReferralInvalidBps() public prank(creator) {
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.createCustomReferralCode(
            MIN_CUSTOM_REFERRAL_CODE,
            11_000,
            false,
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.createCustomReferralCode(
            MIN_CUSTOM_REFERRAL_CODE + 1,
            5001,
            false,
            address(0)
        );
    }

    function testInvalidReferralCodes() public {
        // Test creating a referral code that's in the reserved range
        vm.startPrank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.InvalidReferralCode.selector)
        );
        stp.createCustomReferralCode(
            MIN_CUSTOM_REFERRAL_CODE - 1,
            500,
            false,
            address(0)
        );
        vm.stopPrank();

        // Test minting with a referral code that doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.NonExistantReferralCode.selector)
        );
        stp.mintAdvanced{value: 0.001 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 123,
                purchaseValue: 0.001 ether
            })
        );

        // Test updating a referral code that doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.NonExistantReferralCode.selector)
        );
        stp.updateReferralCode(MIN_CUSTOM_REFERRAL_CODE, 500, address(0));
    }

    function testPermanentReferralCode() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralSet(code);
        stp.createCustomReferralCode(code, 500, true, address(123));

        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.ReferralLocked.selector)
        );
        stp.updateReferralCode(code, 500, address(321));
    }

    function testSetDefaultReferralBps() public {
        vm.startPrank(creator);

        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.DefaultReferralBpsSet(501);
        stp.setDefaultReferralBps(501);
        assertEq(stp.defaultReferralBps(), 501);

        vm.stopPrank();

        // Attempt to set with unauthorized account
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlled.NotAuthorized.selector)
        );
        stp.setDefaultReferralBps(500);

        // Attempt to set with invalid BPS
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.setDefaultReferralBps(10001);
    }

    function testInvalidBpsOfDefaultReferralId() public {
        // Alice mints, which creates tokenId 1 & referral code 1
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);

        uint16 invalidBps = stp.defaultReferralBps() + 1;

        // Alice attempts to update her referral code with BPS above defaultBps
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.updateReferralCode(1, invalidBps, alice);
        vm.stopPrank();
    }

    function testReferrerCanChangeAddress() public {
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);

        // Alice now has referral code ID 1 (her subscription token ID)
        // She can give it to Bob
        stp.updateReferralCode(1, 500, bob);

        vm.stopPrank();
    }

    function testInvalidReferrer() public {
        vm.startPrank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.InvalidReferrer.selector)
        );
        stp.createCustomReferralCode(
            MIN_CUSTOM_REFERRAL_CODE,
            500,
            false,
            address(0)
        );
    }

    function testDefaultReferralTokenId() public {
        uint256 pricePerPeriod = 0.001 ether;
        uint16 rewardBasisPoints = 1000;
        uint256 aliceTokenId = 1;

        tierParams.pricePerPeriod = pricePerPeriod;
        tierParams.initialMintPrice = 0;
        tierParams.rewardBasisPoints = rewardBasisPoints;
        stp = reinitStp();

        // Alice mints, which creates tokenId 1 & referral code 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's referral code
        assertEq(stp.referralDetail(aliceTokenId).referrer, alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.referralDetail(aliceTokenId).basisPoints) /
            MAX_BPS) * stp.curveDetail(0).currentMultiplier;

        // Sub created for Bob using Alice's referral code.
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: aliceTokenId,
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease
        );
    }

    function testLifetimeReferrals() public {
        uint256 pricePerPeriod = 0.0025 ether;
        uint16 rewardBasisPoints = 420;
        uint256 aliceTokenId = 1;

        tierParams.pricePerPeriod = pricePerPeriod;
        tierParams.initialMintPrice = 0;
        tierParams.rewardBasisPoints = rewardBasisPoints;
        stp = reinitStp();

        // Alice mints, which creates tokenId 1 & referral code 1
        vm.startPrank(alice);
        stp.mint{value: pricePerPeriod}(pricePerPeriod);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's referral code
        assertEq(stp.referralDetail(1).referrer, alice);

        uint256 aliceSharesBefore = stp.subscriptionOf(alice).rewardShares;

        uint256 expectedIncrease = ((((pricePerPeriod * rewardBasisPoints) /
            MAX_BPS) * stp.referralDetail(aliceTokenId).basisPoints) /
            MAX_BPS) * stp.curveDetail(0).currentMultiplier;

        // Bob use's Alices sub tokenId as referral code, which
        // makes her the lifetime referrer for his subscription
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 1, // Alice's sub tokenId & referral code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease
        );

        // Bob tries to mint with a different referral code, but it should fail
        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.InvalidReferralCode.selector)
        );
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 2, // Different referral code
                purchaseValue: pricePerPeriod
            })
        );

        // Bob mints with no referral code, which should automatically use Alice as the referrer
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 0, // No referral code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 2
        );

        // Bob can provide Alice's referral code
        vm.expectEmit(true, true, false, true, address(stp));
        emit RewardPoolLib.SharesIssued(alice, expectedIncrease);
        stp.mintAdvanced{value: pricePerPeriod}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 1, // Alice's sub tokenId & referral code
                purchaseValue: pricePerPeriod
            })
        );

        assertEq(
            stp.subscriptionOf(alice).rewardShares,
            aliceSharesBefore + expectedIncrease * 3
        );
    }
}
