// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CurveParams} from "src/types/Rewards.sol";

/// @dev Library for reward curve calculations with support for large period values
library RewardCurveLib {
    using FixedPointMathLib for uint256;

    /// @dev The scaling factor used for percentage calculations (100% = 1e18)
    uint256 constant WAD = 1e18;

    /// @dev Basis points scaling (100% = 10000)
    uint256 constant BASIS_PTS = 1e4;

    /// @dev Maximum chunk size for processing large periods
    uint256 constant MAX_CHUNK_SIZE = 10;

    /// @dev Calculate the current multiplier for the curve using chunked calculations
    /// @dev Formula: base^(numPeriods - periods) where base is formulaBase/10000
    /// @dev Example: For 1% decay per period, use formulaBase = 9900 (0.99)
    function currentMultiplier(
        CurveParams memory curve
    ) internal view returns (uint256 multiplier) {
        if (curve.numPeriods == 0) return curve.minMultiplier;

        uint256 periods = surpassedPeriods(curve);
        if (periods > curve.numPeriods) return curve.minMultiplier;

        uint256 remainingPeriods = curve.numPeriods - periods;
        uint256 base = (uint256(curve.formulaBase) * WAD) / BASIS_PTS;
        multiplier = WAD;

        // Scale down after each multiplication to prevent overflow
        while (remainingPeriods > 0) {
            uint256 chunkSize = remainingPeriods > MAX_CHUNK_SIZE
                ? MAX_CHUNK_SIZE
                : remainingPeriods;

            // Scale down immediately after the power operation
            uint256 chunkResult = base.rpow(chunkSize, WAD);
            // Scale back to basis points early to prevent overflow
            multiplier = (multiplier * chunkResult) / WAD;

            remainingPeriods -= chunkSize;
        }

        // Final scaling to basis points
        multiplier = (multiplier * BASIS_PTS) / WAD;

        if (multiplier < curve.minMultiplier) multiplier = curve.minMultiplier;
    }

    /// @dev Calculate how many periods have passed
    function surpassedPeriods(
        CurveParams memory curve
    ) private view returns (uint256) {
        // Prevents underflow error
        if (block.timestamp <= curve.startTimestamp) {
            return 0;
        }
        return (block.timestamp - curve.startTimestamp) / curve.periodSeconds;
    }
}
