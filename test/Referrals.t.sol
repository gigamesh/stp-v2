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

    function testReferralRewards() public {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        address referrer = address(321);

        vm.startPrank(creator);
        stp.createCustomReferralCode(code, 500, false, referrer);
        vm.stopPrank();

        uint256 balance = referrer.balance;

        vm.expectEmit(true, true, false, true, address(stp));
        emit STPV2.ReferralPayout(1, referrer, code, 5e15);
        stp.mintAdvanced{value: 0.1 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: code,
                purchaseValue: 0.1 ether
            })
        );

        assertEq(referrer.balance, balance + 5e15);
        assertEq(address(stp).balance, 1e17 - 5e15);
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

    function testDefaultReferralTokenId() public {
        // Alice mints, which creates tokenId 1 & referral code 1
        vm.startPrank(alice);
        stp.mint{value: 0.1 ether}(0.1 ether);
        vm.stopPrank();

        // Verify tokenId 1 is Alice's referral code
        assertEq(stp.referralDetail(1).referrer, alice);

        uint256 balance = alice.balance;

        // Bob use's Alices sub tokenId as referral code.
        vm.expectEmit(true, true, false, true, address(stp));
        emit STPV2.ReferralPayout(2, alice, 1, 5e15);
        stp.mintAdvanced{value: 0.1 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referralCode: 1, // Alice's sub tokenId & referral code
                purchaseValue: 0.1 ether
            })
        );

        assertEq(alice.balance, balance + 5e15);
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
}
