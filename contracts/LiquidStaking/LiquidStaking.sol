// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./StElaToken.sol";
import "./interfaces/ICrossChainPayload.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

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

    event Deposit(
        address indexed user,
        address receiver,
        uint256 elaAmountDeposited,
        uint256 stElaAmountReceived
    );

    event WithdrawRequest(address indexed user, uint256 amount);

    event Withdraw(
        address indexed user,
        address receiver,
        uint256 stElaAmountBurned,
        uint256 elaReceived
    );

    event Fund(address indexed user, uint256 elaAmount);

    event Epoch(uint256 indexed epoch, uint256 exchangeRate);

    constructor(
        StElaToken _stEla,
        ICrossChainPayload _crossChainPayload,
        string memory _receivePayloadAddress,
        uint256 _receivePayloadFee
    ) public {
        stEla = _stEla;
        crossChainPayload = _crossChainPayload;
        receivePayloadAddress = _receivePayloadAddress;
        receivePayloadFee = _receivePayloadFee;
        exchangeRate = _EXCHANGE_RATE_DIVIDER;
        currentEpoch = 1;
        stElaTransferOwner = msg.sender;
    }

    receive() external payable {
        totalElaAmountForWithdraw = totalElaAmountForWithdraw.add(msg.value);
        prevTotalElaAmountForWithdraw = totalElaAmountForWithdraw;

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
    function updateEpochFirstStep(uint256 _exchangeRate) external onlyOwner {
        GlideErrors._require(
            _exchangeRate >= exchangeRate,
            GlideErrors.EXCHANGE_RATE_MUST_BE_GREATER_OR_EQUAL_PREVIOUS
        );

        totalWithdrawRequested = totalWithdrawRequested.add(
            stElaEpochTotalWithdrawRequested
        );
        prevStElaEpochTotalWithdrawRequested = totalWithdrawRequested;
        stElaEpochTotalWithdrawRequested = 0;
        currentEpoch = currentEpoch.add(1);
        exchangeRate = _exchangeRate;
        onHold = true;

        emit Epoch(currentEpoch, _exchangeRate);
    }

    /// @dev Second step for update epoch (after amount send to contract)
    function updateEpochSecondStep() external onlyOwner {
        uint256 prevEpochElaForWithdraw = getElaAmountForWithdraw(
            prevStElaEpochTotalWithdrawRequested
        );

        GlideErrors._require(
            prevTotalElaAmountForWithdraw >= prevEpochElaForWithdraw,
            GlideErrors.UPDATE_EPOCH_NO_ENOUGH_ELA
        );
        prevStElaEpochTotalWithdrawRequested = 0;
        prevTotalElaAmountForWithdraw = 0;
        onHold = false;
    }

    /// @dev How much amount needed before updateEpochSecondStep (complete update epoch)
    /// @return uint256 Amount that is needed to be provided before updateEpochSecondStep
    function getUpdateEpochAmount() external view returns (uint256) {
        uint256 elaAmountForWithdraw = getElaAmountForWithdraw(
            prevStElaEpochTotalWithdrawRequested
        );
        if (elaAmountForWithdraw > prevTotalElaAmountForWithdraw) {
            return elaAmountForWithdraw.sub(prevTotalElaAmountForWithdraw);
        }
        return 0;
    }

    /// @dev Deposit ELA amount and get stEla token
    /// @param _stElaReceiver Receiver for stEla token
    function deposit(address _stElaReceiver) external payable {
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
        stEla.mint(_stElaReceiver, amountOut);

        emit Deposit(msg.sender, _stElaReceiver, msg.value, amountOut);
    }

    /// @dev Request withdraw stEla amount and get ELA
    /// @param _amount stEla amount that user requested to withdraw
    function requestWithdraw(uint256 _amount) external {
        GlideErrors._require(
            _amount <= stEla.balanceOf(msg.sender),
            GlideErrors.REQUEST_WITHDRAW_NOT_ENOUGH_AMOUNT
        );

        _withdrawRequestToExecuteTransfer();

        withdrawRequests[msg.sender].stElaAmount = withdrawRequests[msg.sender]
            .stElaAmount
            .add(_amount);
        withdrawRequests[msg.sender].epoch = currentEpoch;

        stElaEpochTotalWithdrawRequested = stElaEpochTotalWithdrawRequested.add(
                _amount
            );

        stEla.transferFrom(msg.sender, address(this), _amount);

        emit WithdrawRequest(msg.sender, _amount);
    }

    /// @dev Withdraw stEla amount and get ELA coin
    /// @param _amount stEla amount that user want to withdraw
    /// @param _receiver Receiver for ELA coin
    function withdraw(uint256 _amount, address _receiver)
        external
        nonReentrant
    {
        _withdrawRequestToExecuteTransfer();

        if (!onHold) {
            if (withdrawForExecutes[msg.sender].stElaOnHoldAmount > 0) {
                withdrawForExecutes[msg.sender]
                    .stElaAmount = withdrawForExecutes[msg.sender]
                    .stElaAmount
                    .add(withdrawForExecutes[msg.sender].stElaOnHoldAmount);
                withdrawForExecutes[msg.sender].stElaOnHoldAmount = 0;
            }
        }

        GlideErrors._require(
            _amount <= withdrawForExecutes[msg.sender].stElaAmount,
            GlideErrors.WITHDRAW_NOT_ENOUGH_AMOUNT
        );
        withdrawForExecutes[msg.sender].stElaAmount = withdrawForExecutes[
            msg.sender
        ].stElaAmount.sub(_amount);

        uint256 elaAmount = getElaAmountForWithdraw(_amount);

        totalWithdrawRequested = totalWithdrawRequested.sub(_amount);
        totalElaAmountForWithdraw = totalElaAmountForWithdraw.sub(elaAmount);

        stEla.burn(address(this), _amount);

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

    function setStElaTransferOwner(address _stElaTransferOwner) external {
        GlideErrors._require(
            msg.sender == stElaTransferOwner,
            GlideErrors.SET_STELA_TRANSFER_OWNER
        );
        stElaTransferOwner = _stElaTransferOwner;
    }

    function transferStElaOwnership(address _newOwner) external {
        GlideErrors._require(
            msg.sender == stElaTransferOwner,
            GlideErrors.TRANSFER_STELA_OWNERSHIP
        );
        stEla.transferOwnership(_newOwner);
    }

    function getElaAmountForWithdraw(uint256 _stElaAmount)
        public
        view
        returns (uint256)
    {
        return _stElaAmount.div(exchangeRate).mul(_EXCHANGE_RATE_DIVIDER);
    }

    function _withdrawRequestToExecuteTransfer() internal {
        if (
            withdrawRequests[msg.sender].stElaAmount > 0 &&
            withdrawRequests[msg.sender].epoch < currentEpoch
        ) {
            if (
                onHold &&
                currentEpoch.sub(withdrawRequests[msg.sender].epoch) == 1
            ) {
                withdrawForExecutes[msg.sender]
                    .stElaOnHoldAmount = withdrawForExecutes[msg.sender]
                    .stElaOnHoldAmount
                    .add(withdrawRequests[msg.sender].stElaAmount);
            } else {
                withdrawForExecutes[msg.sender]
                    .stElaAmount = withdrawForExecutes[msg.sender]
                    .stElaAmount
                    .add(withdrawRequests[msg.sender].stElaAmount);
            }
            withdrawRequests[msg.sender].stElaAmount = 0;
        }
    }
}
