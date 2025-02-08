// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CurveParams} from "src/types/Rewards.sol";

/// @dev Library for reward curve calculations using percentage-based decay
library RewardCurveLib {
    using FixedPointMathLib for uint256;

    /// @dev The scaling factor used for percentage calculations (100% = 1e18)
    uint256 constant WAD = 1e18;

    /// @dev Scales multiplier to effectively act like a fixed-point number with 2 decimal places
    uint256 constant SCALE_FACTOR = 100;

    /// @dev The maximum number of periods a curve can have (prevents overflow)
    uint16 public constant MAX_PERIODS = 10_000;

    /// @dev Calculate the current multiplier for the curve
    /// @dev For a decay rate of X%, the multiplier decreases by X% each period
    /// @dev Example: 50% decay means each period multiplies by 0.5
    function currentMultiplier(
        CurveParams memory curve
    ) internal view returns (uint256 multiplier) {
        // Handle a non-existant or constant curve
        if (curve.numPeriods == 0) return curve.minMultiplier;

        uint256 periods = surpassedPeriods(curve);

        if (periods > curve.numPeriods) return curve.minMultiplier;

        // Calculate (1 - decayRate/100) in WAD precision
        uint256 baseRate = ((100 - curve.decayRate) * WAD) / 100;

        // Start from SCALE_FACTOR (100%) and apply decay for elapsed periods
        multiplier = WAD;
        if (periods > 0) {
            multiplier = baseRate.rpow(periods, WAD);
        }

        // Convert to basis points
        multiplier = (multiplier * SCALE_FACTOR) / WAD;

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
