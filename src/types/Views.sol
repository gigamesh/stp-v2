// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

/*
 * Views are read-only interfaces that can be used to access the state of a contract.
 */

struct SubscriberView {
    /// @dev The tier id of the subscription
    uint16 tierId;
    /// @dev The tokenId for the subscription
    uint64 tokenId;
    /// @dev The expiration timestamp of the subscription
    uint48 expiresAt;
    /// @dev The expiration timestamp of the subscription (excluding granted time)
    uint48 purchaseExpiresAt;
    /// @dev The number of reward shares held
    uint256 rewardShares;
    /// @dev The claimable reward balance
    uint256 rewardBalance;
}

struct ContractView {
    /// @dev The number of tiers
    uint16 tierCount;
    /// @dev The number of subscriptions
    uint64 subCount;
    /// @dev The global supply cap
    uint64 supplyCap;
    /// @dev The transfer recipient address (0x0 for none)
    address transferRecipient;
    /// @dev The token address or 0x0 for ETH
    address currency;
    /// @dev The creator balance
    uint256 creatorBalance;
    /// @dev The total reward curves
    uint8 numCurves;
    /// @dev The number of issued shares
    uint256 rewardShares;
    /// @dev The current reward balance
    uint256 rewardBalance;
    /// @dev The reward slash grace period
    uint32 rewardSlashGracePeriod;
    /// @dev whether the pool is slashable
    bool rewardSlashable;
}

struct CurveView {
    /// @dev the number of periods for which rewards are paid
    uint16 numPeriods;
    /// @dev The decay rate per period (1 = 1% decay, 50 = 50% decay)
    uint8 decayRate;
    /// @dev the period duration in seconds
    uint48 periodSeconds;
    /// @dev the start timestamp for rewards
    uint48 startTimestamp;
    /// @dev the minimum multiplier for rewards (in basis points)
    uint256 minMultiplier;
    /// @dev The current multiplier
    uint256 currentMultiplier;
}
