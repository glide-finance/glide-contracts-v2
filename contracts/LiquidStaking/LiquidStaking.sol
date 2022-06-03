// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/ILiquidStaking.sol";
import "./interfaces/ICrossChainPayload.sol";
import "./stELAToken.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStaking is ILiquidStaking, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 private constant _EXCHANGE_RATE_DIVIDER = 10000;
    uint256 private constant _EXCHANGE_RATE_UPPER_LIMIT = 100;

    stELAToken public immutable stELA;
    ICrossChainPayload public immutable crossChainPayload;

    mapping(address => WithrawRequest) public withdrawRequests;
    mapping(address => WithdrawReady) public withdrawReady;

    address public stELATransferOwner;

    string public receivePayloadAddress;
    uint256 public receivePayloadFee;

    bool public onHold;
    uint256 public exchangeRate;
    uint256 public currentEpoch;
    uint256 public totalELAWithdrawRequested;
    uint256 public currentEpochRequestTotal;
    uint256 public prevEpochRequestTotal;
    uint256 public totalELA;

    constructor(
        stELAToken _stELA,
        ICrossChainPayload _crossChainPayload,
        string memory _receivePayloadAddress,
        uint256 _receivePayloadFee
    ) public {
        stELA = _stELA;
        crossChainPayload = _crossChainPayload;
        receivePayloadAddress = _receivePayloadAddress;
        receivePayloadFee = _receivePayloadFee;
        exchangeRate = _EXCHANGE_RATE_DIVIDER;
        currentEpoch = 1;
        stELATransferOwner = msg.sender;
    }

    receive() external payable onlyOwner {
        totalELA = totalELA.add(msg.value);
        prevEpochRequestTotal = totalELA;

        emit Fund(msg.sender, msg.value);
    }

    function setReceivePayloadAddress(string calldata _receivePayloadAddress)
        external
        payable
        override
        onlyOwner
    {
        GlideErrors._require(
            bytes(_receivePayloadAddress).length == 34,
            GlideErrors.ELASTOS_MAINNET_ADDRESS_LENGTH
        );

        receivePayloadAddress = _receivePayloadAddress;

        emit ReceivePayloadAddressChange(_receivePayloadAddress);
    }

    function setReceivePayloadFee(uint256 _receivePayloadFee)
        external
        payable
        override
        onlyOwner
    {
        receivePayloadFee = _receivePayloadFee;

        emit ReceivePayloadFeeChange(receivePayloadFee);
    }

    function updateEpoch(uint256 _exchangeRate) external override onlyOwner {
        GlideErrors._require(
            _exchangeRate >= exchangeRate,
            GlideErrors.EXCHANGE_RATE_MUST_BE_GREATER_OR_EQUAL_PREVIOUS
        );

        GlideErrors._require(
            _exchangeRate <= exchangeRate.add(_EXCHANGE_RATE_UPPER_LIMIT),
            GlideErrors.EXCHANGE_RATE_UPPER_LIMIT
        );

        GlideErrors._require(!onHold, GlideErrors.STATUS_CANNOT_BE_ONHOLD);

        totalELAWithdrawRequested = totalELAWithdrawRequested.add(
            currentEpochRequestTotal
        );
        currentEpochRequestTotal = 0;
        currentEpoch = currentEpoch.add(1);
        exchangeRate = _exchangeRate;
        onHold = true;

        emit Epoch(currentEpoch, _exchangeRate);
    }

    function enableWithdraw() external override onlyOwner {
        GlideErrors._require(onHold, GlideErrors.STATUS_MUST_BE_ONHOLD);

        GlideErrors._require(
            prevEpochRequestTotal >= totalELAWithdrawRequested,
            GlideErrors.UPDATE_EPOCH_NOT_ENOUGH_ELA
        );
        prevEpochRequestTotal = 0;
        onHold = false;

        emit EnableWithdraw(totalELAWithdrawRequested);
    }

    function getUpdateEpochAmount() external view override returns (uint256) {
        if (totalELAWithdrawRequested > prevEpochRequestTotal) {
            return totalELAWithdrawRequested.sub(prevEpochRequestTotal);
        }
        return 0;
    }

    function deposit() external payable override nonReentrant {
        GlideErrors._require(
            bytes(receivePayloadAddress).length != 0,
            GlideErrors.RECEIVE_PAYLOAD_ADDRESS_ZERO
        );

        uint256 receivePayloadAmount = msg.value.sub(receivePayloadFee);
        uint256 amountOut = (receivePayloadAmount.mul(_EXCHANGE_RATE_DIVIDER))
            .div(exchangeRate);
        stELA.mint(msg.sender, amountOut);

        crossChainPayload.receivePayload{value: msg.value}(
            receivePayloadAddress,
            msg.value,
            receivePayloadFee
        );

        emit Deposit(msg.sender, msg.value, amountOut);
    }

    function requestWithdraw(uint256 _stELAAmount) external override nonReentrant {
        GlideErrors._require(
            _stELAAmount <= stELA.balanceOf(msg.sender),
            GlideErrors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        _withdrawRequestToReadyTransfer();

        uint256 elaAmount = getELAAmountForWithdraw(_stELAAmount);

        withdrawRequests[msg.sender].elaAmount = withdrawRequests[msg.sender]
            .elaAmount
            .add(elaAmount);
        withdrawRequests[msg.sender].epoch = currentEpoch;

        currentEpochRequestTotal = currentEpochRequestTotal.add(elaAmount);

        stELA.burn(msg.sender, _stELAAmount);

        emit WithdrawRequest(msg.sender, _stELAAmount, elaAmount);
    }

    function withdraw(uint256 _elaAmount) external override nonReentrant {
        _withdrawRequestToReadyTransfer();

        if (!onHold) {
            if (withdrawReady[msg.sender].elaOnHoldAmount > 0) {
                withdrawReady[msg.sender].elaAmount = withdrawReady[msg.sender]
                    .elaAmount
                    .add(withdrawReady[msg.sender].elaOnHoldAmount);
                withdrawReady[msg.sender].elaOnHoldAmount = 0;
            }
        }

        GlideErrors._require(
            _elaAmount <= withdrawReady[msg.sender].elaAmount,
            GlideErrors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawReady[msg.sender].elaAmount = withdrawReady[msg.sender]
            .elaAmount
            .sub(_elaAmount);

        totalELAWithdrawRequested = totalELAWithdrawRequested.sub(_elaAmount);
        totalELA = totalELA.sub(_elaAmount);

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(msg.sender).call{value: _elaAmount}(
            ""
        );
        GlideErrors._require(
            successTransfer,
            GlideErrors.WITHDRAW_TRANSFER_NOT_SUCCESS
        );

        emit Withdraw(msg.sender, _elaAmount);
    }

    function setstELATransferOwner(address _stELATransferOwner)
        external
        override
    {
        GlideErrors._require(
            msg.sender == stELATransferOwner,
            GlideErrors.SET_STELA_TRANSFER_OWNER
        );
        stELATransferOwner = _stELATransferOwner;

        emit StELATransferOwner(_stELATransferOwner);
    }

    function transferstELAOwnership(address _newOwner) external override {
        GlideErrors._require(
            msg.sender == stELATransferOwner,
            GlideErrors.TRANSFER_STELA_OWNERSHIP
        );
        stELA.transferOwnership(_newOwner);

        emit StELAOwner(_newOwner);
    }

    function getELAAmountForWithdraw(uint256 _stELAAmount)
        public
        view
        override
        returns (uint256)
    {
        return _stELAAmount.mul(exchangeRate).div(_EXCHANGE_RATE_DIVIDER);
    }

    /// @dev Check if user has existing withdrawal request and add to ready status if funds are available
    function _withdrawRequestToReadyTransfer() internal {
        if (
            withdrawRequests[msg.sender].elaAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            if (
                onHold &&
                currentEpoch.sub(withdrawRequests[msg.sender].epoch) == 1
            ) {
                withdrawReady[msg.sender].elaOnHoldAmount = withdrawReady[
                    msg.sender
                ].elaOnHoldAmount.add(withdrawRequests[msg.sender].elaAmount);
            } else {
                withdrawReady[msg.sender].elaAmount = withdrawReady[msg.sender]
                    .elaAmount
                    .add(withdrawRequests[msg.sender].elaAmount)
                    .add(withdrawReady[msg.sender].elaOnHoldAmount);
                withdrawReady[msg.sender].elaOnHoldAmount = 0;
            }
            withdrawRequests[msg.sender].elaAmount = 0;
        }
    }
}
