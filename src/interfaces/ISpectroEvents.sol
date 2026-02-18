// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISpectroEvents{
    event IntendSettled(
        address indexed solver,
        address indexed beneficiary,
        uint256 amount,
        uint256 fee
    );

    event IntentFulfilled(
        address indexed user,
        address indexed solver,
        uint256 amount,
        uint256 targetChainId,
        bytes32 conditionHash
    );

    ///////////////////////////////
    // Emergency shutdown events //
    ///////////////////////////////
    event EmergencyShutdown(address triggeredBy);
}