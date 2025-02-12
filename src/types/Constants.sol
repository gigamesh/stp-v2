// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Currency} from "../libraries/CurrencyLib.sol";

/// @dev The maximum basis points
uint16 constant MAX_BPS = 10_000;

/// @dev The maximum fee in basis points
uint16 constant MAX_FEE_BPS = 1250;

/// @dev The maximum referral bonus in basis points
uint16 constant MAX_REFERRAL_BPS = 5000;

/// @dev The protocol fee in basis points
uint16 constant PROTOCOL_FEE_BPS = 50;

/// @dev The deploy fee currency (ETH)
Currency constant DEPLOY_FEE_CURRENCY = Currency.wrap(address(0));

/// @dev Any custom referral code must be higher than this number
/// It reserves part of the range for the tokenId codes
/// created when subscriptions are minted.
uint256 constant MIN_CUSTOM_REFERRAL_CODE = 100_000_000_000;

/// @dev Common error for invalid basis point values
error InvalidBasisPoints();
