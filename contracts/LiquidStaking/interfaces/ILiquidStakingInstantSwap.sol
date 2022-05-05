// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ILiquidStakingInstantSwap {
    event Fund(address indexed user, uint256 elaAmount);

    event FeeRate(uint256 newFeeRate);

    event StELAWithdraw(address indexed user, uint256 amount);

    event ElaWithdraw(address indexed user, uint256 amount);

    event Swap(
        address indexed user,
        uint256 stELAAmountSend,
        uint256 elaAmountReceived,
        address receiver
    );

    /// @param _feeRate For 0% fee, set 10000. For 1% fee, set 9900. For 0.5%, set 9950.
    function setFee(uint256 _feeRate) external;

    /// @dev Admin function to withdraw stELA from contract and convert back to ELA using LiquidStaking.sol
    /// @param _stELAAmount stELA amount to withdraw
    function withdrawstELA(uint256 _stELAAmount) external;

    function withdrawEla(uint256 _elaAmount) external;

    /// @dev Allows a user to pay a fee to swap stELA to ELA instantly without wait period
    /// @param _stELAAmount stELA amount to swap
    /// @param _receiver Receiver for ELA
    function swap(uint256 _stELAAmount, address _receiver) external;
}
