// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./LiquidStaking.sol";
import "./StElaToken.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStakingInstantSwap is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 private constant _FEE_DIVIDER = 10000;

    StElaToken private immutable stEla;
    LiquidStaking private immutable liquidStaking;

    uint256 public elaAmount;
    uint256 public feeRate;
    uint256 public stElaAmount;

    event Fund(
        address indexed user, 
        uint256 elaAmount
    );

    event Swap(
        address indexed user,
        uint256 stElaAmountSend,
        uint256 elaAmountReceived,
        address receiver
    );

    constructor(
        StElaToken _stEla,
        LiquidStaking _liquidStaking, 
        uint256 _feeRate
    ) public feeInRange(_feeRate) {
        stEla = _stEla;
        liquidStaking = _liquidStaking;
        feeRate = _feeRate;
    }

    modifier feeInRange(uint256 _feeRate) {
        GlideErrors._require(
            _feeRate >= 9900 && _feeRate <= _FEE_DIVIDER,
            GlideErrors.FEE_RATE_IS_NOT_IN_RANGE
        );
        _;
    }

    receive() external payable {
        elaAmount = elaAmount.add(msg.value);

        emit Fund(msg.sender, msg.value);
    }

    function setFee(uint256 _feeRate) external onlyOwner feeInRange(_feeRate) {
        feeRate = _feeRate;
    }

    function withdrawStEla(uint256 _stElaAmount, address _receiver) external onlyOwner {
        GlideErrors._require(
            _stElaAmount <= stElaAmount,
            GlideErrors.NO_ENOUGH_STELA_IN_CONTRACT
        );

        stElaAmount = stElaAmount.sub(_stElaAmount);
        stEla.transfer(_receiver, _stElaAmount);
    }  

    function swap(uint256 _stElaAmount, address _receiver)
        external
        nonReentrant
    {
        uint256 amountForSwap = _stElaAmount.mul(feeRate).div(_FEE_DIVIDER);
        stElaAmount = stElaAmount.add(_stElaAmount);

        uint256 elaAmountForWithdraw = liquidStaking.getElaAmountForWithdraw(
            amountForSwap
        );
        GlideErrors._require(
            elaAmount >= elaAmountForWithdraw,
            GlideErrors.NO_ENOUGH_ELA_IN_CONTRACT
        );

        stEla.transferFrom(msg.sender, address(this), _stElaAmount);

        (bool successTransfer, ) = payable(_receiver).call{
            value: elaAmountForWithdraw
        }("");
        GlideErrors._require(
            successTransfer,
            GlideErrors.SWAP_TRANSFER_NOT_SUCCEESS
        );

        emit Swap(msg.sender, _stElaAmount, elaAmountForWithdraw, _receiver);
    }
}
