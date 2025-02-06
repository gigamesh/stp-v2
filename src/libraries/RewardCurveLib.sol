// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CurveParams} from "src/types/Rewards.sol";

/// @dev Library for reward curve calculations
library RewardCurveLib {
    using FixedPointMathLib for uint256;

    /// @dev The scaling factor used for percentage calculations (100% = 1e18)
    uint256 constant WAD = 1e18;

    /// @dev Calculate the current multiplier for the curve
    /// @dev Formula: base^(numPeriods - periods) where base is formulaBase/10000
    /// @dev Example: For 1% decay per period, use formulaBase = 9900 (0.99)
    function currentMultiplier(
        CurveParams memory curve
    ) internal view returns (uint256 multiplier) {
        if (curve.numPeriods == 0) return curve.minMultiplier;

        uint256 periods = surpassedPeriods(curve);
        if (periods > curve.numPeriods) return curve.minMultiplier;

        // Convert basis points to WAD format
        uint256 base = (uint256(curve.formulaBase) * WAD) / 10000;

        // Calculate power: base^(numPeriods - periods)
        multiplier = base.rpow(curve.numPeriods - periods, WAD);

        // Scale back down from WAD
        multiplier = multiplier / 1e9;

        if (multiplier < curve.minMultiplier) multiplier = curve.minMultiplier;
    }

    /// @dev How many periods have passed
    function surpassedPeriods(
        CurveParams memory curve
    ) private view returns (uint256) {
        return (block.timestamp - curve.startTimestamp) / curve.periodSeconds;
    }
}
