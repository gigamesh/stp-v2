// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CurveParams} from "src/types/Rewards.sol";

/// @dev Library for reward curve calculations using percentage-based decay
library RewardCurveLib {
    using FixedPointMathLib for uint256;

    /// @dev The scaling factor used for percentage calculations (100% = 1e18)
    uint256 constant WAD = 1e18;

    /// @dev Basis points scaling (100% = 10000)
    uint256 constant BASIS_POINTS = 1e4;

    /// @dev Calculate the current multiplier for the curve
    /// @dev For a decay rate of X%, the multiplier decreases by X% each period
    /// @dev Example: 50% decay means each period multiplies by 0.5
    function currentMultiplier(
        CurveParams memory curve
    ) internal view returns (uint256 multiplier) {
        if (curve.numPeriods == 0) return curve.minMultiplier; // Handle a non-existant or constant curve

        uint256 periods = surpassedPeriods(curve);

        if (periods > curve.numPeriods) return curve.minMultiplier;

        // Calculate (1 - decayRate/100) in WAD precision
        uint256 baseRate = ((100 - curve.decayRate) * WAD) / 100;

        // Start from BASIS_POINTS (100%) and apply decay for elapsed periods
        multiplier = WAD;
        if (periods > 0) {
            multiplier = baseRate.rpow(periods, WAD);
        }

        // Convert to basis points
        multiplier = (multiplier * BASIS_POINTS) / WAD;

        if (multiplier < curve.minMultiplier) {
            return curve.minMultiplier;
        }

        return multiplier;
    }

    /// @dev Calculate how many periods have passed
    function surpassedPeriods(
        CurveParams memory curve
    ) private view returns (uint256) {
        if (block.timestamp <= curve.startTimestamp) {
            return 0;
        }
        return (block.timestamp - curve.startTimestamp) / curve.periodSeconds;
    }
}
