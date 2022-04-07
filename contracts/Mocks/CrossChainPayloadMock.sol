// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../LiquidStaking/interfaces/ICrossChainPayload.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract CrossChainPayloadMock is ICrossChainPayload {
    using SafeMath for uint256;
    event PayloadReceived(
        string _addr,
        uint256 _amount,
        uint256 _crosschainamount,
        address indexed _sender
    );
    event EtherDeposited(
        address indexed _sender,
        uint256 _amount,
        address indexed _black
    );

    function receivePayload(
        string memory _addr,
        uint256 _amount,
        uint256 _fee
    ) public payable override {
        require(msg.value == _amount);
        require(_fee >= 100000000000000 && _fee % 10000000000 == 0);
        require(_amount % 10000000000 == 0 && _amount.sub(_fee) >= _fee);
        emit PayloadReceived(_addr, _amount, _amount.sub(_fee), msg.sender);
        emit EtherDeposited(msg.sender, msg.value, address(0));
    }

    receive() external payable {
        revert();
    }
}
