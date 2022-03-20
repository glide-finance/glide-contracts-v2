// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./StElaToken.sol";
import "./interfaces/ICrossChainPayload.sol";
import "../Helpers/GlideErrors.sol";

contract LiquidStaking is Ownable {
    uint256 private constant _EXCHANGE_RATE_DIVIDER = 10000;
    StElaToken private immutable stEla;
    ICrossChainPayload private immutable crossChainPayload;

    string private receivePayloadAddress;
    uint256 private receivePayloadFee;

    uint256 public exchangeRate;
    uint256 public currentEpoch;
    uint256 public totalWithdrawRequested;
    uint256 public epochTotalWithdrawRequested;
    uint256 public totalElaAmountForWithdraw;

    struct WithrawRequest {
        uint256 stElaAmount;
        uint256 epoch;
    }

    mapping(address => WithrawRequest) public withdrawRequests;
    mapping(address => uint256) public withdrawForExecute;

    constructor(StElaToken _stEla, ICrossChainPayload _crossChainPayload) {
        stEla = _stEla;
        crossChainPayload = _crossChainPayload;
        exchangeRate = _EXCHANGE_RATE_DIVIDER;
        currentEpoch = 1;
    }

    receive() external payable {
        totalElaAmountForWithdraw += msg.value;
    }

    function setReceivePayloadAddress(string memory _receivePayloadAddress)
        external
        payable
        onlyOwner
    {
        receivePayloadAddress = _receivePayloadAddress;
    }

    function setReceivePayloadFee(uint256 _receivePayloadFee)
        external
        payable
        onlyOwner
    {
        receivePayloadFee = _receivePayloadFee;
    }

    function updateEpoch(uint256 _exchangeRate) external onlyOwner {
        totalWithdrawRequested += epochTotalWithdrawRequested;
        epochTotalWithdrawRequested = 0;
        currentEpoch += 1;
        exchangeRate = _exchangeRate;
    }

    function getUpdateEpochAmount() external view returns (uint256) {
        return totalWithdrawRequested - totalElaAmountForWithdraw;
    }

    function deposit(address _stElaReceiver) external payable {
        uint256 amountOut = (msg.value * exchangeRate) / _EXCHANGE_RATE_DIVIDER;
        crossChainPayload.receivePayload{value: amountOut}(
            receivePayloadAddress,
            amountOut,
            receivePayloadFee
        );
        stEla.mint(_stElaReceiver, amountOut);
    }

    function requestWithdraw(uint256 _amount) external {
        _require(
            _amount <= stEla.balanceOf(msg.sender),
            Errors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        if (
            withdrawRequests[msg.sender].stElaAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            withdrawForExecute[msg.sender] += withdrawRequests[msg.sender]
                .stElaAmount;
            withdrawRequests[msg.sender].stElaAmount = 0;
        }
        withdrawRequests[msg.sender].stElaAmount += _amount;
        withdrawRequests[msg.sender].epoch = currentEpoch;

        epochTotalWithdrawRequested += _amount;

        stEla.transfer(address(this), _amount);
    }

    function withdraw(uint256 _amount, address _receiver) external {
        if (withdrawRequests[msg.sender].epoch < currentEpoch) {
            withdrawForExecute[msg.sender] += withdrawRequests[msg.sender]
                .stElaAmount;
            withdrawRequests[msg.sender].stElaAmount = 0;
        }

        _require(
            _amount <= withdrawForExecute[msg.sender],
            Errors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawForExecute[msg.sender] -= _amount;

        uint256 elaAmount = _amount / (exchangeRate / _EXCHANGE_RATE_DIVIDER);

        totalWithdrawRequested -= _amount;
        totalElaAmountForWithdraw -= elaAmount;

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(_receiver).call{value: elaAmount}(
            ""
        );
        _require(successTransfer, Errors.WITHDRAW_TRANSFER_NOT_SUCCEESS);

        stEla.burn(address(this), _amount);
    }
}
