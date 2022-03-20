// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICrossChainPayload {
    function receivePayload(
        string memory _addr,
        uint256 _amount,
        uint256 _fee
    ) external payable;
}
