// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../TestImports.t.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract RewardCurveTestShim {
    function currentMultiplier(
        CurveParams memory params
    ) external view returns (uint256 multiplier) {
        return RewardCurveLib.currentMultiplier(params);
    }

    function test() public {}
}

contract RewardCurveLibTest is BaseTest {
    using FixedPointMathLib for uint256;

    RewardCurveTestShim public shim = new RewardCurveTestShim();

    function defaults() internal pure returns (CurveParams memory) {
        // 50% decay per period (halves each period)
        return
            CurveParams({
                numPeriods: 6,
                decayRate: 50, // 50% decay per period
                periodSeconds: 86_400,
                startTimestamp: 0,
                minMultiplier: 0
            });
    }

    function testNoDecay() public {
        CurveParams memory params = defaults();
        params.numPeriods = 0;
        params.minMultiplier = 1;
        params.startTimestamp = uint48(1);
        assertEq(shim.currentMultiplier(params), 1);
        vm.warp(block.timestamp + 365 days);
        assertEq(shim.currentMultiplier(params), 1);
    }

    function testSinglePeriod() public {
        CurveParams memory params = defaults();
        // Initial: Should be 100%
        assertEq(shim.currentMultiplier(params), 100);

        // After 1 period: Should decay by 50%
        vm.warp(block.timestamp + 1 + 1 days);
        assertEq(shim.currentMultiplier(params), 50);
    }

    function testZeroMin() public {
        CurveParams memory params = defaults();
        vm.warp(block.timestamp + 30 days);
        assertEq(params.minMultiplier, 0);
        assertEq(shim.currentMultiplier(params), 0);
    }

    function testOneMin() public {
        CurveParams memory params = defaults();
        params.minMultiplier = 1;
        vm.warp(block.timestamp + 20 days);
        assertEq(shim.currentMultiplier(params), 1);
    }

    function testMinMultiplierIsMin() public {
        CurveParams memory params = defaults();
        params.minMultiplier = 3;

        vm.warp(block.timestamp + 2 days);
        assertEq(shim.currentMultiplier(params), 25); // 50% decay twice
        vm.warp(block.timestamp + 7 days);
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }

    function testFuzzDecay(uint16 numPeriods) public {
        vm.assume(numPeriods > 0);

        // This has been tested with RewardCurveLib.MAX_PERIODS but it's too slow.
        // Most subscriptions will have < 100 periods
        vm.assume(numPeriods <= 100);

        CurveParams memory params = defaults();
        params.numPeriods = numPeriods;
        uint256 start = block.timestamp;

        // Calculate base rate for decay
        uint256 baseRate = ((100 - params.decayRate) * RewardCurveLib.WAD) /
            100;

        for (uint256 period = 0; period < params.numPeriods; period++) {
            vm.warp(start + (params.periodSeconds * period));

            // Calculate expected value
            uint256 expected = baseRate.rpow(period, RewardCurveLib.WAD);
            expected =
                (expected * RewardCurveLib.SCALE_FACTOR) /
                RewardCurveLib.WAD;

            assertEq(shim.currentMultiplier(params), expected);
        }

        vm.warp(start + (params.periodSeconds * (params.numPeriods + 1)) + 1);
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }

    function testDecayRateBoundaries() public {
        CurveParams memory params = defaults();

        // Test 0% decay
        params.decayRate = 0;
        assertEq(shim.currentMultiplier(params), RewardCurveLib.SCALE_FACTOR); // Stays at 100%

        // Test 100% decay
        params.decayRate = 100;
        vm.warp(block.timestamp + params.periodSeconds);
        assertEq(shim.currentMultiplier(params), 0); // Complete decay
    }
}
