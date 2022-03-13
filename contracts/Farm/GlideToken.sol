// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// GlideToken with Governance.
contract GlideToken is ERC20("Glide", "GLIDE"), Ownable {
    uint256 private constant _maxTotalSupply = 50000000e18; // 50,000,000 max supply

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(
            totalSupply() + _amount <= _maxTotalSupply,
            "ERC20: minting more than MaxTotalSupply"
        );

        _mint(_to, _amount);
    }

    // Returns maximum total supply of the token
    function getMaxTotalSupply() external pure returns (uint256) {
        return _maxTotalSupply;
    }
}
