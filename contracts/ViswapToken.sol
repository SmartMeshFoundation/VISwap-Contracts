// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import "./libraries/ERC20.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeMath.sol";


contract ViswapToken is ERC20("ViSwap", "VSP"), Ownable {
    using SafeMath for uint256;
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
