// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./StElaToken.sol";
import "./interfaces/ICrossChainPayload.sol";
import "../Helpers/GlideErrors.sol";

contract LiquidStaking is Ownable {
    uint256 private constant _EXCHANGE_RATE_DIVIDER = 10000;
    StElaToken private immutable stEla;
    ICrossChainPayload private immutable crossChainPayload;

    address public stElaTransferOwner;

    string public receivePayloadAddress;
    uint256 public receivePayloadFee;

    bool public onHold;
    uint256 public exchangeRate;
    uint256 public currentEpoch;
    uint256 public totalWithdrawRequested;
    uint256 public prevStElaEpochTotalWithdrawRequested;
    uint256 public stElaEpochTotalWithdrawRequested;
    uint256 public prevTotalElaAmountForWithdraw;
    uint256 public totalElaAmountForWithdraw;

    struct WithrawRequest {
        uint256 stElaAmount;
        uint256 epoch;
    }

    struct WithdrawForExecute {
        uint256 stElaAmount;
        uint256 stElaOnHoldAmount;
    }

    mapping(address => WithrawRequest) public withdrawRequests;
    mapping(address => WithdrawForExecute) public withdrawForExecutes;

    constructor(StElaToken _stEla, ICrossChainPayload _crossChainPayload) {
        stEla = _stEla;
        crossChainPayload = _crossChainPayload;
        exchangeRate = _EXCHANGE_RATE_DIVIDER;
        currentEpoch = 1;
        stElaTransferOwner = msg.sender;
    }

    receive() external payable {
        totalElaAmountForWithdraw += msg.value;
        prevTotalElaAmountForWithdraw = totalElaAmountForWithdraw;
    }

    /// @dev Set mainchain address for crosschain tranfer where ELA will be deposit
    /// @param _receivePayloadAddress Mainchain address
    function setReceivePayloadAddress(string memory _receivePayloadAddress)
        external
        payable
        onlyOwner
    {
        receivePayloadAddress = _receivePayloadAddress;
    }

    /// @dev Set fee that will be payed for crosschain transfer when user deposit ELA
    /// @param _receivePayloadFee Fee amount
    function setReceivePayloadFee(uint256 _receivePayloadFee)
        external
        payable
        onlyOwner
    {
        receivePayloadFee = _receivePayloadFee;
    }

    /// @dev First step for update epoch (before amount send to contract)
    /// @param _exchangeRate Exchange rate 
    function updateEpochFirstStep(uint256 _exchangeRate) external onlyOwner {
        totalWithdrawRequested += stElaEpochTotalWithdrawRequested;
        prevStElaEpochTotalWithdrawRequested = totalWithdrawRequested;
        stElaEpochTotalWithdrawRequested = 0;
        currentEpoch += 1;
        exchangeRate = _exchangeRate;
        onHold = true;
    }

    /// @dev Second step for update epoch (after amount send to contract)
    function updateEpochSecondStep() external onlyOwner {
        uint256 prevEpochElaForWithdraw = _getElaAmountForWithdraw(
            prevStElaEpochTotalWithdrawRequested
        );

        _require(
            prevTotalElaAmountForWithdraw == prevEpochElaForWithdraw,
            Errors.UPDATE_EPOCH_NO_ENOUGH_ELA
        );
        prevStElaEpochTotalWithdrawRequested = 0;
        prevTotalElaAmountForWithdraw = 0;
        onHold = false;
    }

    /// @dev How much amount needed before updateEpochSecondStep (complete update epoch)
    /// @return uint256 Amount that is needed to be provided before updateEpochSecondStep
    function getUpdateEpochAmount() external view returns (uint256) {
        return
            _getElaAmountForWithdraw(prevStElaEpochTotalWithdrawRequested) -
            prevTotalElaAmountForWithdraw;
    }

    /// @dev Deposit ELA amount and get stEla token
    /// @param _stElaReceiver Receiver for stEla token
    function deposit(address _stElaReceiver) external payable {
        _require(
            bytes(receivePayloadAddress).length != 0,
            Errors.RECEIVE_PAYLOAD_ADDRESS_ZERO
        );

        crossChainPayload.receivePayload{value: msg.value}(
            receivePayloadAddress,
            msg.value,
            receivePayloadFee
        );

        uint256 amountOut = (msg.value * exchangeRate) / _EXCHANGE_RATE_DIVIDER;
        stEla.mint(_stElaReceiver, amountOut);
    }

    /// @dev Request withdraw stEla amount and get ELA
    /// @param _amount stEla amount that user requested to withdraw
    function requestWithdraw(uint256 _amount) external {
        _require(
            _amount <= stEla.balanceOf(msg.sender),
            Errors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        _withdrawRequestToExecuteTransfer();

        withdrawRequests[msg.sender].stElaAmount += _amount;
        withdrawRequests[msg.sender].epoch = currentEpoch;

        stElaEpochTotalWithdrawRequested += _amount;

        stEla.transferFrom(msg.sender, address(this), _amount);
    }

    /// @dev Withdraw stEla amount and get ELA coin
    /// @param _amount stEla amount that user want to withdraw
    /// @param _receiver Receiver for ELA coin
    function withdraw(uint256 _amount, address _receiver) external {
        _withdrawRequestToExecuteTransfer();

        if (!onHold) {
            if (withdrawForExecutes[msg.sender].stElaOnHoldAmount > 0) {
                withdrawForExecutes[msg.sender]
                    .stElaAmount += withdrawForExecutes[msg.sender]
                    .stElaOnHoldAmount;
                withdrawForExecutes[msg.sender].stElaOnHoldAmount = 0;
            }
        }

        _require(
            _amount <= withdrawForExecutes[msg.sender].stElaAmount,
            Errors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawForExecutes[msg.sender].stElaAmount -= _amount;

        uint256 elaAmount = _getElaAmountForWithdraw(_amount);

        totalWithdrawRequested -= _amount;
        totalElaAmountForWithdraw -= elaAmount;

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(_receiver).call{value: elaAmount}(
            ""
        );
        _require(successTransfer, Errors.WITHDRAW_TRANSFER_NOT_SUCCEESS);

        stEla.burn(address(this), _amount);
    }

    function setStElaTransferOwner(address _stElaTransferOwner) external {
        _require(
            msg.sender == stElaTransferOwner,
            Errors.SET_STELA_TRANSFER_OWNER
        );
        stElaTransferOwner = _stElaTransferOwner;
    }

    function transferStElaOwnership(address _newOwner) external {
        _require(
            msg.sender == stElaTransferOwner,
            Errors.TRANSFER_STELA_OWNERSHIP
        );
        stEla.transferOwnership(_newOwner);
    }

    function _getElaAmountForWithdraw(uint256 _stElaAmount)
        internal
        view
        returns (uint256)
    {
        return (_stElaAmount / exchangeRate) * _EXCHANGE_RATE_DIVIDER;
    }

    function _withdrawRequestToExecuteTransfer() internal {
        if (
            withdrawRequests[msg.sender].stElaAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            if (
                onHold && currentEpoch - withdrawRequests[msg.sender].epoch == 1
            ) {
                withdrawForExecutes[msg.sender]
                    .stElaOnHoldAmount += withdrawRequests[msg.sender]
                    .stElaAmount;
            } else {
                withdrawForExecutes[msg.sender].stElaAmount += withdrawRequests[
                    msg.sender
                ].stElaAmount;
            }
            withdrawRequests[msg.sender].stElaAmount = 0;
        }
    }
}
