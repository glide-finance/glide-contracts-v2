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
    uint256 public totalWithdrawRequested;
    uint256 public currentEpochRequestTotal;
    uint256 public prevEpochDepositTotal;
    uint256 public totalELAForWithdraw;

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
        totalELAForWithdraw = totalELAForWithdraw.add(msg.value);
        prevEpochDepositTotal = totalELAForWithdraw;

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

        totalWithdrawRequested = totalWithdrawRequested.add(
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

        uint256 prevEpochELAForWithdraw = getELAAmountForWithdraw(
            totalWithdrawRequested
        );

        GlideErrors._require(
            prevEpochDepositTotal >= prevEpochELAForWithdraw,
            GlideErrors.UPDATE_EPOCH_NOT_ENOUGH_ELA
        );
        prevEpochDepositTotal = 0;
        onHold = false;

        emit EnableWithdraw(prevEpochELAForWithdraw);
    }

    function getUpdateEpochAmount() external view override returns (uint256) {
        uint256 elaAmountForWithdraw = getELAAmountForWithdraw(
            totalWithdrawRequested
        );
        if (elaAmountForWithdraw > prevEpochDepositTotal) {
            return elaAmountForWithdraw.sub(prevEpochDepositTotal);
        }
        return 0;
    }

    function deposit() external payable override {
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

    function requestWithdraw(uint256 _amount) external override {
        GlideErrors._require(
            _amount <= stELA.balanceOf(msg.sender),
            GlideErrors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        _withdrawRequestToReadyTransfer();

        withdrawRequests[msg.sender].stELAAmount = withdrawRequests[msg.sender]
            .stELAAmount
            .add(_amount);
        withdrawRequests[msg.sender].epoch = currentEpoch;

        currentEpochRequestTotal = currentEpochRequestTotal.add(_amount);

        stELA.transferFrom(msg.sender, address(this), _amount);

        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external override nonReentrant {
        _withdrawRequestToReadyTransfer();

        if (!onHold) {
            if (withdrawReady[msg.sender].stELAOnHoldAmount > 0) {
                withdrawReady[msg.sender].stELAAmount = withdrawReady[
                    msg.sender
                ].stELAAmount.add(withdrawReady[msg.sender].stELAOnHoldAmount);
                withdrawReady[msg.sender].stELAOnHoldAmount = 0;
            }
        }

        GlideErrors._require(
            _amount <= withdrawReady[msg.sender].stELAAmount,
            GlideErrors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawReady[msg.sender].stELAAmount = withdrawReady[msg.sender]
            .stELAAmount
            .sub(_amount);

        uint256 elaAmount = getELAAmountForWithdraw(_amount);

        totalWithdrawRequested = totalWithdrawRequested.sub(_amount);
        totalELAForWithdraw = totalELAForWithdraw.sub(elaAmount);

        stELA.burn(address(this), _amount);

        // solhint-disable-next-line avoid-low-level-calls
        (bool successTransfer, ) = payable(msg.sender).call{value: elaAmount}(
            ""
        );
        GlideErrors._require(
            successTransfer,
            GlideErrors.WITHDRAW_TRANSFER_NOT_SUCCESS
        );

        emit Withdraw(msg.sender, _amount, elaAmount);
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
        return _stELAAmount.div(exchangeRate).mul(_EXCHANGE_RATE_DIVIDER);
    }

    /// @dev Check if user has existing withdrawal request and add to ready status if funds are available
    function _withdrawRequestToReadyTransfer() internal {
        if (
            withdrawRequests[msg.sender].stELAAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            if (
                onHold &&
                currentEpoch.sub(withdrawRequests[msg.sender].epoch) == 1
            ) {
                withdrawReady[msg.sender].stELAOnHoldAmount = withdrawReady[
                    msg.sender
                ].stELAOnHoldAmount.add(
                        withdrawRequests[msg.sender].stELAAmount
                    );
            } else {
                withdrawReady[msg.sender].stELAAmount = withdrawReady[
                    msg.sender
                ].stELAAmount.add(withdrawRequests[msg.sender].stELAAmount).add(
                        withdrawReady[msg.sender].stELAOnHoldAmount
                    );
                withdrawReady[msg.sender].stELAOnHoldAmount = 0;
            }
            withdrawRequests[msg.sender].stELAAmount = 0;
        }
    }
}
