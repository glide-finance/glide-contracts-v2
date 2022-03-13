// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../Helpers/GlideErrors.sol";
import "./StElaToken.sol";

contract LiquidStaking is Ownable {
    StElaToken private stEla;

    uint256 public stakedEla;
    uint256 public exchangeRate;
    uint256 public currentEpoch;
    uint256 public totalWithdrawRequested;

    struct WithrawRequest {
        uint256 elaAmount;
        uint256 epoch;
    }

    mapping(address => WithrawRequest) private withdrawRequests;
    mapping(address => uint256) private withdrawAmounts;

    constructor(StElaToken _stEla) {
        stEla = _stEla;
        exchangeRate = 1;
        currentEpoch = 1;
    }

    function updateEpoch(uint256 _exchangeRate) external payable onlyOwner {
        _require(totalWithdrawRequested == msg.value, Errors.UPDATE_EPOCH);
        exchangeRate = _exchangeRate;
        currentEpoch += 1;
        totalWithdrawRequested = 0;
    }

    function withdrawStakedEla(uint256 _amount, address _receiver)
        external
        onlyOwner
    {
        _require(
            _amount <= stakedEla,
            Errors.WITHDRAW_STAKED_ELA_NOT_ENOUGH_AMOUNT
        );
        stakedEla -= _amount;

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(_receiver).call{value: _amount}("");
        _require(
            successTransfer,
            Errors.WITHDRAW_STAKED_ELA_TRANSFER_NOT_SUCCEESS
        );
    }

    function deposit(address _stElaReceiver) external payable {
        stakedEla += msg.value;
        uint256 amountOut = msg.value * exchangeRate;
        stEla.mint(_stElaReceiver, amountOut);
    }

    function requestWithdraw(uint256 _amount) external {
        _require(
            _amount <= stEla.balanceOf(msg.sender),
            Errors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        stEla.burn(msg.sender, _amount);

        if (
            withdrawRequests[msg.sender].elaAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            withdrawAmounts[msg.sender] += withdrawRequests[msg.sender]
                .elaAmount;
            withdrawRequests[msg.sender].elaAmount = 0;
        }

        uint256 receiveElaAmount = _amount / exchangeRate;
        totalWithdrawRequested += receiveElaAmount;
        withdrawRequests[msg.sender].elaAmount += receiveElaAmount;
        withdrawRequests[msg.sender].epoch = currentEpoch;
    }

    function withdraw(uint256 _amount, address _receiver) external {
        if (withdrawRequests[msg.sender].epoch < currentEpoch) {
            withdrawAmounts[msg.sender] += withdrawRequests[msg.sender]
                .elaAmount;
            withdrawRequests[msg.sender].elaAmount = 0;
        }

        _require(
            _amount <= withdrawAmounts[msg.sender],
            Errors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawAmounts[msg.sender] -= _amount;

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(_receiver).call{value: _amount}("");
        _require(successTransfer, Errors.WITHDRAW_TRANSFER_NOT_SUCCEESS);
    }
}
