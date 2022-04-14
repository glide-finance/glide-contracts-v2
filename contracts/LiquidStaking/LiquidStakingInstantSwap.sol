// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./LiquidStaking.sol";
import "./stELAToken.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStakingInstantSwap is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 private constant _FEE_DIVIDER = 10000;

    stELAToken private immutable stELA;
    LiquidStaking private immutable liquidStaking;

    uint256 public elaAmount;
    uint256 public feeRate;
    uint256 public stELAAmount;

    event Fund(address indexed user, uint256 elaAmount);

    event Swap(
        address indexed user,
        uint256 stELAAmountSend,
        uint256 elaAmountReceived,
        address receiver
    );

    constructor(
        stELAToken _stELA,
        LiquidStaking _liquidStaking,
        uint256 _feeRate
    ) public feeInRange(_feeRate) {
        stELA = _stELA;
        liquidStaking = _liquidStaking;
        feeRate = _feeRate;
    }

    /// @dev Fee should be between 0% (10000) and 1% (9900)
    modifier feeInRange(uint256 _feeRate) {
        GlideErrors._require(
            _feeRate >= 9900 && _feeRate <= _FEE_DIVIDER,
            GlideErrors.FEE_RATE_IS_NOT_IN_RANGE
        );
        _;
    }

    /// @dev Add amount of ELA available in contract for instant swap
    receive() external payable {
        elaAmount = elaAmount.add(msg.value);

        emit Fund(msg.sender, msg.value);
    }

    /// @param _feeRate For 0% fee, set 10000. For 1% fee, set 9900. For 0.5%, set 9950.
    function setFee(uint256 _feeRate) external onlyOwner feeInRange(_feeRate) {
        feeRate = _feeRate;
    }

    /// @dev Admin function to withdraw stELA from contract and convert back to ELA using LiquidStaking.sol 
    /// @param _stELAAmount stELA amount to withdraw
    /// @param _receiver Receiver for stELA
    function withdrawstELA(uint256 _stELAAmount, address _receiver)
        external
        onlyOwner
    {
        GlideErrors._require(
            _stELAAmount <= stELAAmount,
            GlideErrors.NOT_ENOUGH_STELA_IN_CONTRACT
        );

        stELAAmount = stELAAmount.sub(_stELAAmount);
        stELA.transfer(_receiver, _stELAAmount);
    }

    function withdrawEla(uint256 _elaAmount, address _receiver)
        external
        onlyOwner
    {
        GlideErrors._require(
            _elaAmount <= elaAmount,
            GlideErrors.NO_ENOUGH_WITHDRAW_ELA_IN_CONTRACT
        );

        elaAmount = elaAmount.sub(_elaAmount);
        (bool successTransfer, ) = payable(_receiver).call{value: _elaAmount}(
            ""
        );
        GlideErrors._require(
            successTransfer,
            GlideErrors.WITHDRAW_TRANSFER_NOT_SUCCEESS
        );
    }

    /// @dev Allows a user to pay a free to swap stELA to ELA instantly without wait period
    /// @param _stELAAmount stELA amount to swap
    /// @param _receiver Receiver for ELA
    function swap(uint256 _stELAAmount, address _receiver)
        external
        nonReentrant
    {
        uint256 amountForSwap = _stELAAmount.mul(feeRate).div(_FEE_DIVIDER);
        stELAAmount = stELAAmount.add(_stELAAmount);

        uint256 elaAmountForWithdraw = liquidStaking.getELAAmountForWithdraw(
            amountForSwap
        );
        GlideErrors._require(
            elaAmount >= elaAmountForWithdraw,
            GlideErrors.NOT_ENOUGH_ELA_IN_CONTRACT
        );

        stELA.transferFrom(msg.sender, address(this), _stELAAmount);

        (bool successTransfer, ) = payable(_receiver).call{
            value: elaAmountForWithdraw
        }("");
        GlideErrors._require(
            successTransfer,
            GlideErrors.SWAP_TRANSFER_NOT_SUCCEESS
        );

        emit Swap(msg.sender, _stELAAmount, elaAmountForWithdraw, _receiver);
    }
}
