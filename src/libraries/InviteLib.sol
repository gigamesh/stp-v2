// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import "../types/Constants.sol";

/// @dev Library for storing invite codes and their associated percentages
library InviteLib {
    error InviteLocked();

    error InvalidInviteCode();

    error NonExistantInviteCode();

    error InvalidInviter();

    error CodeAlreadyExists();

    /// @dev A invite code was created or updated
    event InviteSet(uint256 indexed code);

    /// @dev A invite code was destroyed (set to 0)
    event InviteDestroyed(uint256 indexed code);

    /// @dev The default invite BPS was set
    event DefaultInviteBpsSet(uint16 bps);

    /// @dev Struct for holding details of a invite code
    struct Code {
        /// @dev The percentage of the reward shares to give to the inviter
        uint16 basisPoints;
        /// @dev Whether this code can be updated once set (mutable or not)
        bool permanent;
        /// @dev A specific address (0x0 for any address)
        address inviter;
    }

    struct State {
        /// @dev Referal code details
        mapping(uint256 => Code) codes;
        /// @dev The BPS set for the default invite code set for each subscription token
        uint16 defaultBps;
    }

    /// @dev Basic validation and storage for a invite code. A single call was used to reduce size
    function setInvite(
        State storage state,
        uint256 code,
        Code memory settings
    ) internal {
        if (state.codes[code].permanent) revert InviteLocked();
        if (settings.basisPoints == 0) {
            delete state.codes[code];
            emit InviteDestroyed(code);
            return;
        }
        if (settings.basisPoints > MAX_REFERRAL_BPS)
            revert InvalidBasisPoints();

        if (settings.inviter == address(0)) revert InvalidInviter();

        state.codes[code] = settings;
        emit InviteSet(code);
    }
}
