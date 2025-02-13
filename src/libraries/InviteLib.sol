// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import "../types/Constants.sol";

/// @dev Library for storing inviter token ids and their associated percentages
library InviteLib {
    error InviteLocked();

    error InvalidInviterId();

    error NonExistantInviter();

    error InvalidInviter();

    error CodeAlreadyExists();

    /// @dev A inviter was created or updated
    event InviterSet(uint256 indexed inviterId, address inviter);

    /// @dev A inviter token id was destroyed (set to 0)
    event InviteDestroyed(uint256 indexed code);

    /// @dev The default invite BPS was set
    event InviteBpsSet(uint16 bps);

    /// @dev Struct for holding details of a inviter token id
    struct Code {
        /// @dev The percentage of the reward shares to give to the inviter
        uint16 basisPoints;
        /// @dev Whether this code can be updated once set (mutable or not)
        bool permanent;
        /// @dev A specific address (0x0 for any address)
        address inviter;
    }

    struct State {
        /// @dev Inviter token ID to address mapping
        mapping(uint256 => address) inviters;
        /// @dev The BPS set for the default inviter token id set for each subscription token
        uint16 bps;
    }

    /// @dev Set address of inviter
    function setInviter(
        State storage state,
        uint256 inviterId,
        address inviter
    ) internal {
        if (inviter == address(0)) revert InvalidInviter();

        state.inviters[inviterId] = inviter;
        emit InviterSet(inviterId, inviter);
    }
}
