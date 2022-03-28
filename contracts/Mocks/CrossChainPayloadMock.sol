// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../LiquidStaking/interfaces/ICrossChainPayload.sol";

contract CrossChainPayloadMock is ICrossChainPayload {
    function receivePayload(
        string memory,
        uint256 _amount,
        uint256
    ) external payable override {
        // solhint-disable-next-line reason-string
        require(_amount == msg.value);
    }
}
