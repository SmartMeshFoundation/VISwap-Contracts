// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './interfaces/IViswapPair.sol';
import './interfaces/IViswapFactory.sol';
import './libraries/Ownable.sol';
import './ViswapPair.sol';

contract ViswapFactory is Ownable {
    address public feeTo;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);


    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function _msgSender() internal view override returns (address payable) {
        return tx.origin;
    }

    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, 'Viswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Viswap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Viswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ViswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IViswapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }
}
