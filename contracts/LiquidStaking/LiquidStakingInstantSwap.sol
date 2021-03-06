// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/ILiquidStaking.sol";
import "./interfaces/ILiquidStakingInstantSwap.sol";
import "../Helpers/GlideErrors.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidStakingInstantSwap is
    ILiquidStakingInstantSwap,
    Ownable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 private constant _FEE_DIVIDER = 10000;

    IERC20 public immutable stELA;
    ILiquidStaking public immutable liquidStaking;

    uint256 public elaAmount;
    uint256 public feeRate;
    uint256 public stELAAmount;

    constructor(
        IERC20 _stELA,
        ILiquidStaking _liquidStaking,
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
    receive() external payable onlyOwner {
        elaAmount = elaAmount.add(msg.value);

        emit Fund(msg.sender, msg.value);
    }

    function setFee(uint256 _feeRate)
        external
        override
        onlyOwner
        feeInRange(_feeRate)
    {
        feeRate = _feeRate;

        emit FeeRate(feeRate);
    }

    function withdrawstELA(uint256 _stELAAmount) external override onlyOwner {
        GlideErrors._require(
            _stELAAmount <= stELAAmount,
            GlideErrors.NOT_ENOUGH_STELA_IN_CONTRACT
        );

        stELAAmount = stELAAmount.sub(_stELAAmount);
        stELA.safeTransfer(msg.sender, _stELAAmount);

        emit StELAWithdraw(msg.sender, _stELAAmount);
    }

    function withdrawEla(uint256 _elaAmount) external override onlyOwner {
        GlideErrors._require(
            _elaAmount <= elaAmount,
            GlideErrors.NO_ENOUGH_WITHDRAW_ELA_IN_CONTRACT
        );

        elaAmount = elaAmount.sub(_elaAmount);
        (bool successTransfer, ) = payable(msg.sender).call{value: _elaAmount}(
            ""
        );
        GlideErrors._require(
            successTransfer,
            GlideErrors.WITHDRAW_TRANSFER_NOT_SUCCESS
        );

        emit ElaWithdraw(msg.sender, _elaAmount);
    }

    function swap(uint256 _stELAAmount, address _receiver)
        external
        override
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

        stELA.safeTransferFrom(msg.sender, address(this), _stELAAmount);

        elaAmount = elaAmount.sub(elaAmountForWithdraw);
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
