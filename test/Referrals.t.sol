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
        stp.setReferralCode(code, 500, false, address(0));
        assertEq(stp.referralDetail(code).basisPoints, 500);
        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralDestroyed(code);
        stp.setReferralCode(code, 0, false, address(0));
        assertEq(stp.referralDetail(code).basisPoints, 0);
    }

    function testCreateReferralInvalidBps() public prank(creator) {
        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.setReferralCode(
            MIN_CUSTOM_REFERRAL_CODE,
            11_000,
            false,
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidBasisPoints.selector));
        stp.setReferralCode(MIN_CUSTOM_REFERRAL_CODE, 5001, false, address(0));
    }

    function testInvalidReferralCodes() public {
        uint256 balance = charlie.balance;
        stp.mintAdvanced{value: 0.001 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referrer: charlie,
                referralCode: 10,
                purchaseValue: 0.001 ether
            })
        );
        assertEq(charlie.balance, balance);

        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.InvalidReferralCode.selector)
        );
        stp.setReferralCode(
            MIN_CUSTOM_REFERRAL_CODE - 1,
            500,
            false,
            address(0)
        );
    }

    function testPermanentReferralCode() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralSet(code);
        stp.setReferralCode(code, 500, true, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(ReferralLib.ReferralLocked.selector)
        );
        stp.setReferralCode(code, 500, false, address(0));
    }

    function testControlledReferral() public prank(creator) {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.expectEmit(true, true, false, true, address(stp));
        emit ReferralLib.ReferralSet(code);
        stp.setReferralCode(code, 500, true, bob);

        uint256 balance = charlie.balance;
        stp.mintAdvanced{value: 0.1 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referrer: charlie,
                referralCode: code,
                purchaseValue: 0.1 ether
            })
        );
        assertEq(charlie.balance, balance);

        uint256 feeBalance = bob.balance;
        stp.mintAdvanced{value: 0.1 ether}(
            MintParams({
                tierId: 1,
                recipient: charlie,
                referrer: bob,
                referralCode: code,
                purchaseValue: 0.1 ether
            })
        );
        assertEq(bob.balance, feeBalance + 5e15);
    }

    function testReferralRewards() public {
        uint256 code = MIN_CUSTOM_REFERRAL_CODE;

        vm.startPrank(creator);
        stp.setReferralCode(code, 500, false, address(0));
        vm.stopPrank();

        uint256 balance = charlie.balance;

        vm.expectEmit(true, true, false, true, address(stp));
        emit STPV2.ReferralPayout(1, charlie, code, 5e15);
        stp.mintAdvanced{value: 0.1 ether}(
            MintParams({
                tierId: 1,
                recipient: bob,
                referrer: charlie,
                referralCode: code,
                purchaseValue: 0.1 ether
            })
        );
        vm.stopPrank();
        assertEq(charlie.balance, balance + 5e15);
        assertEq(address(stp).balance, 1e17 - 5e15);
    }

    function testTokenIdReferral() public {
        // TODO
    }
}
