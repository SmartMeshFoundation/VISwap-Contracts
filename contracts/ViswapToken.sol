// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import "./libraries/ERC20.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeMath.sol";


contract ViswapToken is ERC20, Ownable {
    using SafeMath for uint256;

    constructor (
        uint256 _totalSupply,
        address _airdrop,
        address _premint,
        address _team,
        address _notary
    ) ERC20("VISwap", "VIT") {

        require(_airdrop != address(0), "_airdrop address cannot be 0");
        require(_premint != address(0), "_premint address cannot be 0");
        require(_team != address(0), "_team address cannot be 0");
        require(_notary != address(0), "_notary address cannot be 0");

        _mint(_airdrop, _totalSupply.mul(5).div(100)); //5% for airdrop
        _mint(_premint, _totalSupply.mul(5).div(100)); //5% for premint
        _mint(_team, _totalSupply.mul(6).div(100));    //6% for premint
        _mint(_notary, _totalSupply.mul(30).div(100)); //30% for notary
    }


    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
