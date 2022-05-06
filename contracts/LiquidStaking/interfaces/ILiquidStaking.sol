// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./ICrossChainPayload.sol";

interface ILiquidStaking {
    struct WithrawRequest {
        uint256 elaAmount;
        uint256 epoch;
    }

    struct WithdrawReady {
        uint256 elaAmount;
        uint256 elaOnHoldAmount;
    }

    event Deposit(
        address indexed user,
        uint256 elaAmountDeposited,
        uint256 stELAAmountReceived
    );

    event WithdrawRequest(
        address indexed user,
        uint256 amount,
        uint256 elaAmount
    );

    event Withdraw(address indexed user, uint256 elaReceived);

    event Fund(address indexed user, uint256 elaAmount);

    event Epoch(uint256 indexed epoch, uint256 exchangeRate);

    event ReceivePayloadAddressChange(string indexed newAddress);

    event ReceivePayloadFeeChange(uint256 newFee);

    event EnableWithdraw(uint256 elaAmountForWithdraw);

    event StELATransferOwner(address indexed newAddress);

    event StELAOwner(address indexed newAddress);

    /// @dev Set mainchain address for crosschain transfer where ELA will be deposit
    /// @param _receivePayloadAddress Mainchain address
    function setReceivePayloadAddress(string calldata _receivePayloadAddress)
        external
        payable;

    /// @dev Set fee that will be paid for crosschain transfer when user deposit ELA
    /// @param _receivePayloadFee Fee amount
    function setReceivePayloadFee(uint256 _receivePayloadFee) external payable;

    /// @dev First step for update epoch (before amount send to contract)
    /// @param _exchangeRate Exchange rate
    function updateEpoch(uint256 _exchangeRate) external;

    /// @dev Second step for update epoch (after balance for withdrawal received)
    function enableWithdraw() external;

    /// @dev How much amount needed before beginEpoch (complete update epoch)
    /// @return uint256 Amount that is needed to be provided before enableWithdraw
    function getUpdateEpochAmount() external view returns (uint256);

    /// @dev Deposit ELA amount and get stELA token
    function deposit() external payable;

    /// @dev Request withdraw stELA amount and get ELA
    /// @param _amount stELA amount that user requested to withdraw
    function requestWithdraw(uint256 _amount) external;

    /// @dev Withdraw stELA amount and get ELA coin
    /// @param _amount stELA amount that the user wants to withdraw
    function withdraw(uint256 _amount) external;

    /// @dev Transfer owner will be set to a TimeLock contract
    /// @param _stELATransferOwner address that controls ownership of the stELA token
    function setstELATransferOwner(address _stELATransferOwner) external;

    /// @dev Allow for the migration of the stELA token contract if upgrades are made to the LiquidStaking functions
    /// @param _newOwner target address for transferring ownership of the stELA token
    function transferstELAOwnership(address _newOwner) external;

    /// @dev Convert stELA to ELA based on current exchange rate
    /// @param _stELAAmount amount of stELA token to be withdrawn
    function getELAAmountForWithdraw(uint256 _stELAAmount)
        external
        view
        returns (uint256);
}
