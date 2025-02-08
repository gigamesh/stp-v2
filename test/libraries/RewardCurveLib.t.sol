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
        // Base of 2 in the old system becomes 20000 in basis points (2.0 * 10000)
        return
            CurveParams({
                numPeriods: 6,
                periodSeconds: 86_400,
                startTimestamp: 0,
                minMultiplier: 0,
                formulaBase: 20000
            });
    }

    /// Curve Tests ///

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
        // 2^6 = 64 in the old system
        assertEq(shim.currentMultiplier(params), 64 * RewardCurveLib.BASIS_PTS);
        vm.warp(block.timestamp + 1 + 1 days);
        // 2^5 = 32 in the old system
        assertEq(shim.currentMultiplier(params), 32 * RewardCurveLib.BASIS_PTS);
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
        params.minMultiplier = 42069;
        vm.warp(block.timestamp + 2 days);
        assertEq(shim.currentMultiplier(params), 16_0000);
        vm.warp(block.timestamp + 7 days);
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
        vm.warp(block.timestamp + 100 days);
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }

    function testZeroPeriods() public {
        CurveParams memory params = defaults();
        params.numPeriods = 0;
        assertEq(shim.currentMultiplier(params), 0);
    }

    function testFuzzDecay(uint8 periods) public {
        vm.assume(periods > 0);
        vm.assume(periods <= 64);

        CurveParams memory params = defaults();
        params.numPeriods = periods;
        uint256 start = block.timestamp;

        // Convert the base (2.0) to proper basis points format once
        uint256 base = (params.formulaBase * RewardCurveLib.WAD) /
            RewardCurveLib.BASIS_PTS; // 2.0 in WAD format

        for (uint256 i = 0; i <= params.numPeriods; i++) {
            vm.warp(start + (params.periodSeconds * i) + 1);

            // Calculate expected value using the same fixed-point math as the library
            uint256 remainingPeriods = params.numPeriods - i;
            uint256 expected = base.rpow(remainingPeriods, RewardCurveLib.WAD);
            expected =
                (expected * RewardCurveLib.BASIS_PTS) /
                RewardCurveLib.WAD;

            assertEq(shim.currentMultiplier(params), expected);
        }

        vm.warp(start + (params.periodSeconds * (params.numPeriods + 1)) + 1);
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }

    function testLargePeriodChunking() public {
        CurveParams memory params = defaults();

        // TODO: test with larger values
        params.numPeriods = 130;

        uint256 start = block.timestamp;
        // Test at beginning
        assertGt(shim.currentMultiplier(params), 0);

        // Test after exactly MAX_CHUNK_SIZE periods
        vm.warp(start + (params.periodSeconds * RewardCurveLib.MAX_CHUNK_SIZE));
        uint256 midMultiplier = shim.currentMultiplier(params);
        assertGt(midMultiplier, params.minMultiplier);

        // Test after all periods
        vm.warp(start + (params.periodSeconds * (params.numPeriods + 1)));
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }

    function testVariousFormulaBases() public {
        CurveParams memory params = defaults();
        params.numPeriods = 4;

        // Test with 0.5 (5000 basis points)
        params.formulaBase = 5000;
        assertEq(shim.currentMultiplier(params), 625); // 0.5^4 * 10000

        // Test with 1.5 (15000 basis points)
        params.formulaBase = 15000;
        assertEq(shim.currentMultiplier(params), 50625); // 1.5^4 * 10000
    }

    function testDifferentPeriodDurations() public {
        CurveParams memory params = defaults();

        // Test with 1 hour periods
        params.periodSeconds = 3600;
        uint256 start = block.timestamp;
        vm.warp(start + 3600);
        uint256 hourlyMultiplier = shim.currentMultiplier(params);

        // Reset and test with 1 day periods
        params.periodSeconds = 86400;
        vm.warp(start + 86400);
        uint256 dailyMultiplier = shim.currentMultiplier(params);

        assertEq(hourlyMultiplier, dailyMultiplier);
    }

    function testFutureStartTimestamp() public {
        uint256 initBlockTimestamp = block.timestamp;
        // Need to start by jumping forward because the
        // contract logic assumes block.timestamp is not zero
        vm.warp(initBlockTimestamp + 100 days);

        CurveParams memory params = defaults();
        params.startTimestamp = uint48(block.timestamp + 1 days);

        // Before start
        assertEq(shim.currentMultiplier(params), 64 * RewardCurveLib.BASIS_PTS);

        // At exact start
        vm.warp(params.startTimestamp);
        assertEq(shim.currentMultiplier(params), 64 * RewardCurveLib.BASIS_PTS);

        // After start
        vm.warp(params.startTimestamp + params.periodSeconds);
        assertEq(shim.currentMultiplier(params), 32 * RewardCurveLib.BASIS_PTS);
    }

    function testMinMultiplierBoundary() public {
        CurveParams memory params = defaults();
        params.minMultiplier = 10000; // 1.0 in basis points

        // Should never go below minMultiplier
        vm.warp(
            block.timestamp + (params.periodSeconds * params.numPeriods * 2)
        );
        assertEq(shim.currentMultiplier(params), params.minMultiplier);
    }
}
