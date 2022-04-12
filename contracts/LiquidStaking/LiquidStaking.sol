// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./stELAToken.sol";
import "./interfaces/ICrossChainPayload.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 private constant _EXCHANGE_RATE_DIVIDER = 10000;
    stELAToken private immutable stELA;
    ICrossChainPayload private immutable crossChainPayload;

    address public stELATransferOwner;

    string public receivePayloadAddress;
    uint256 public receivePayloadFee;

    bool public onHold;
    uint256 public exchangeRate;
    uint256 public currentEpoch;
    uint256 public totalWithdrawRequested;
    uint256 public prevEpochRequestTotal;
    uint256 public currentEpochRequestTotal;
    uint256 public prevEpochDepositTotal;
    uint256 public totalELAForWithdraw;

    struct WithrawRequest {
        uint256 stELAAmount;
        uint256 epoch;
    }

    struct WithdrawReady {
        uint256 stELAAmount;
        uint256 stELAOnHoldAmount;
    }

    mapping(address => WithrawRequest) public withdrawRequests;
    mapping(address => WithdrawReady) public withdrawReady;

    event Deposit(
        address indexed user,
        address receiver,
        uint256 elaAmountDeposited,
        uint256 stELAAmountReceived
    );

    event WithdrawRequest(address indexed user, uint256 amount);

    event Withdraw(
        address indexed user,
        address receiver,
        uint256 stELAAmountBurned,
        uint256 elaReceived
    );

    event Fund(address indexed user, uint256 elaAmount);

    event Epoch(uint256 indexed epoch, uint256 exchangeRate);

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

    receive() external payable {
        totalELAForWithdraw = totalELAForWithdraw.add(msg.value);
        prevEpochDepositTotal = totalELAForWithdraw;

        emit Fund(msg.sender, msg.value);
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
    function updateEpoch(uint256 _exchangeRate) external onlyOwner {
        GlideErrors._require(
            _exchangeRate >= exchangeRate,
            GlideErrors.EXCHANGE_RATE_MUST_BE_GREATER_OR_EQUAL_PREVIOUS
        );

        totalWithdrawRequested = totalWithdrawRequested.add(
            currentEpochRequestTotal
        );
        prevEpochRequestTotal = totalWithdrawRequested;
        currentEpochRequestTotal = 0;
        currentEpoch = currentEpoch.add(1);
        exchangeRate = _exchangeRate;
        onHold = true;

        emit Epoch(currentEpoch, _exchangeRate);
    }

    /// @dev Second step for update epoch (after balance for withdrawal received)
    function enableWithdraw() external onlyOwner {
        uint256 prevEpochELAForWithdraw = getELAAmountForWithdraw(
            prevEpochRequestTotal
        );

        GlideErrors._require(
            prevEpochDepositTotal >= prevEpochELAForWithdraw,
            GlideErrors.UPDATE_EPOCH_NOT_ENOUGH_ELA
        );
        prevEpochRequestTotal = 0;
        prevEpochDepositTotal = 0;
        onHold = false;
    }

    /// @dev How much amount needed before beginEpoch (complete update epoch)
    /// @return uint256 Amount that is needed to be provided before updateEpochSecondStep
    function getUpdateEpochAmount() external view returns (uint256) {
        uint256 elaAmountForWithdraw = getELAAmountForWithdraw(
            prevEpochRequestTotal
        );
        if (elaAmountForWithdraw > prevEpochDepositTotal) {
            return elaAmountForWithdraw.sub(prevEpochDepositTotal);
        }
        return 0;
    }

    /// @dev Deposit ELA amount and get stELA token
    /// @param _stELAReceiver Receiver for stELA token
    function deposit(address _stELAReceiver) external payable {
        GlideErrors._require(
            bytes(receivePayloadAddress).length != 0,
            GlideErrors.RECEIVE_PAYLOAD_ADDRESS_ZERO
        );

        crossChainPayload.receivePayload{value: msg.value}(
            receivePayloadAddress,
            msg.value,
            receivePayloadFee
        );

        uint256 amountOut = (msg.value.mul(_EXCHANGE_RATE_DIVIDER)).div(
            exchangeRate
        );
        stELA.mint(_stELAReceiver, amountOut);

        emit Deposit(msg.sender, _stELAReceiver, msg.value, amountOut);
    }

    /// @dev Request withdraw stELA amount and get ELA
    /// @param _amount stELA amount that user requested to withdraw
    function requestWithdraw(uint256 _amount) external {
        GlideErrors._require(
            _amount <= stELA.balanceOf(msg.sender),
            GlideErrors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        _withdrawRequestToExecuteTransfer();

        withdrawRequests[msg.sender].stELAAmount = withdrawRequests[msg.sender]
            .stELAAmount
            .add(_amount);
        withdrawRequests[msg.sender].epoch = currentEpoch;

        currentEpochRequestTotal = currentEpochRequestTotal.add(_amount);

        stELA.transferFrom(msg.sender, address(this), _amount);

        emit WithdrawRequest(msg.sender, _amount);
    }

    /// @dev Withdraw stELA amount and get ELA coin
    /// @param _amount stELA amount that user want to withdraw
    /// @param _receiver Receiver for ELA coin
    function withdraw(uint256 _amount, address _receiver)
        external
        nonReentrant
    {
        _withdrawRequestToExecuteTransfer();

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
        (bool successTransfer, ) = payable(_receiver).call{value: elaAmount}(
            ""
        );
        GlideErrors._require(
            successTransfer,
            GlideErrors.WITHDRAW_TRANSFER_NOT_SUCCEESS
        );

        emit Withdraw(msg.sender, _receiver, _amount, elaAmount);
    }

    function setstELATransferOwner(address _stELATransferOwner) external {
        GlideErrors._require(
            msg.sender == stELATransferOwner,
            GlideErrors.SET_STELA_TRANSFER_OWNER
        );
        stELATransferOwner = _stELATransferOwner;
    }

    function transferstELAOwnership(address _newOwner) external {
        GlideErrors._require(
            msg.sender == stELATransferOwner,
            GlideErrors.TRANSFER_STELA_OWNERSHIP
        );
        stELA.transferOwnership(_newOwner);
    }

    function getELAAmountForWithdraw(uint256 _stELAAmount)
        public
        view
        returns (uint256)
    {
        return _stELAAmount.div(exchangeRate).mul(_EXCHANGE_RATE_DIVIDER);
    }

    function _withdrawRequestToExecuteTransfer() internal {
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
                ].stELAAmount.add(withdrawRequests[msg.sender].stELAAmount);
            }
            withdrawRequests[msg.sender].stELAAmount = 0;
        }
    }
}
