// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {PRBMath} from "@prb/math/PRBMath.sol";
import {CurveParams} from "src/types/Rewards.sol";

/// @dev Library for reward curve calculations with support for gradual decay
library RewardCurveLib {
    using PRBMath for uint256;

    /// @notice The scale factor used for percentage calculations (100% = 1e18)
    uint256 constant SCALE = 1e18;

    /// @dev Calculate the current multiplier for the curve
    /// @dev For integer base curves: base ^ (numPeriods - periods)
    /// @dev For percentage decay curves: startMultiplier * (1 - decayPercent)^periods
    function currentMultiplier(
        CurveParams memory curve
    ) internal view returns (uint256 multiplier) {
        if (curve.numPeriods == 0) return curve.minMultiplier;

        uint256 periods = surpassedPeriods(curve);
        if (periods > curve.numPeriods) return curve.minMultiplier;

        // If formulaBase is 0 or 1, treat it as a percentage decay
        // where formulaBase represents decay per period in basis points (1 = 0.01%)
        if (curve.formulaBase <= 1) {
            // Start with a high multiplier (1e18) and decay it by the specified percentage
            uint256 startMultiplier = SCALE;
            uint256 decayPercent = curve.formulaBase * 1e14; // Convert basis points to percentage in SCALE

            // Calculate (1 - decayPercent)^periods using PRBMath
            uint256 decayFactor = SCALE - decayPercent;
            multiplier = startMultiplier.mulPow(decayFactor, periods, SCALE);

            // Scale back to reasonable numbers while maintaining precision
            multiplier = multiplier / 1e9;
        } else {
            // Original integer base calculation
            multiplier =
                uint256(curve.formulaBase) ** (curve.numPeriods - periods);
        }

        if (multiplier < curve.minMultiplier) multiplier = curve.minMultiplier;
    }

    /// @dev How many periods have passed, so we can compute the current multiplier
    function surpassedPeriods(
        CurveParams memory curve
    ) private view returns (uint256) {
        return (block.timestamp - curve.startTimestamp) / curve.periodSeconds;
    }
}
