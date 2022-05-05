// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// solhint-disable-next-line contract-name-camelcase
contract stELAToken is ERC20("Staked ELA", "stELA"), Ownable {
    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (LiquidStaking).
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev Creates `_amount` token from `_from`. Must only be called by the owner (LiquidStaking).
    function burn(address _from, uint256 _amount) external onlyOwner {
        _burn(_from, _amount);
    }
}
