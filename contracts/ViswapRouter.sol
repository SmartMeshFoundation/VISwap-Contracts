// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './libraries/SafeMath.sol';
import './libraries/FullMath.sol';
import './interfaces/IViswapFactory.sol';
import './interfaces/IViswapPair.sol';
import './interfaces/IERC20.sol';
import './libraries/TransferHelper.sol';


interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint) external;
}

//Router is only for add/remove liquidity and swap
//put/cancel limit order should direct interplay with the pair contract
contract ViswapRouter {
    using SafeMath for uint256;

    address public immutable factory;
    address public immutable WETH;

    constructor (address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'ViswapRouter: EXPIRED');
        _;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function getPair (address tokenA, address tokenB) internal view returns(address)  {
        return IViswapFactory(factory).getPair(tokenA<tokenB?tokenA:tokenB, tokenA<tokenB?tokenB:tokenA);
    }
    

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 remainedA, uint256 remainedB, address pair) {
        // create the pair if it doesn't exist yet
        pair = getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IViswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB,) = IViswapPair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserveA, reserveB) : (reserveB, reserveA);
        if (reserveA == 0 && reserveB == 0) {
            return (0, 0, pair);
        } else {
            uint amountBOptimal = amountA.mul(reserveB) / reserveA;
            if (amountBOptimal <= amountB) {
                remainedB = amountB - amountBOptimal;
            } else {
                uint amountAOptimal = amountB.mul(reserveA) / reserveB;
                assert(amountAOptimal <= amountA);
                remainedA = amountA - amountAOptimal;
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (uint256 remainedA, uint256 remainedB, address pair) = _addLiquidity(tokenA, tokenB, amountAIn, amountBIn);
        amountA = amountAIn.sub(remainedA);
        amountB = amountBIn.sub(remainedB);
        require(amountA >= amountAMin && amountB >= amountBMin, 'ViswapRouter: Slip Alert');
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IViswapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenIn,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (uint256 remainedToken, uint256 remainedETH, address pair) = _addLiquidity(token, WETH, amountTokenIn, msg.value);
        amountToken = amountTokenIn.sub(remainedToken);
        amountETH = msg.value.sub(remainedETH);
        require(amountToken >= amountTokenMin && amountETH >= amountETHMin, 'ViswapRouter: SLIP ALERT');
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IViswapPair(pair).mint(to);
        // refund dust eth, if any
        if (remainedETH > 0) TransferHelper.safeTransferETH(msg.sender, remainedETH);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 share,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        address pair = getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(pair, msg.sender, pair, share);
        (amountA, amountB) = IViswapPair(pair).burn(address(this));
        (amountA, amountB) = tokenA < tokenB ? (amountA, amountB) : (amountB, amountA);
        require(amountA >= amountAMin && amountB >= amountBMin, 'ViswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if (tokenA == WETH) {
            IWETH(WETH).withdraw(amountA);
            TransferHelper.safeTransferETH(to, amountA);
        } else {
            TransferHelper.safeTransfer(tokenA, to, amountA);
        }
        if (tokenB == WETH) {
            IWETH(WETH).withdraw(amountB);
            TransferHelper.safeTransferETH(to, amountB);
        } else {
            TransferHelper.safeTransfer(tokenB, to, amountB);
        } 
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256 amountIn, address[] memory path, address _to) internal returns(uint256) {
        uint[] memory amounts = getAmountsOut(amountIn, path);
        for (uint i; i < path.length - 1; i++) {
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = path[i] < path[i + 1] ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? getPair(path[i + 1], path[i + 2]) : _to;
            IViswapPair(getPair(path[i], path[i + 1])).swap(amount0Out, amount1Out, to);
        }
        return amounts[amounts.length - 1];
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, getPair(path[0], path[1]), amountIn
        );
        amountOut = _swap(amountIn, path, to);
        require(amountOut >= amountOutMin, 'ViswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256 amountOut)
    {
        require(path[0] == WETH, 'ViswapRouter: INVALID_PATH');
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(getPair(path[0], path[1]), msg.value));
        amountOut = _swap(msg.value, path, to);
        require(amountOut >= amountOutMin, 'ViswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        ensure(deadline)
        returns (uint256 amountOut)
    {
        require(path[path.length - 1] == WETH, 'ViswapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, getPair(path[0], path[1]), amountIn
        );
        amountOut = _swap(amountIn, path, address(this));
        require(amountOut >= amountOutMin, 'ViswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'ViswapRouter: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'ViswapRouter: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountsOut(uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'ViswapRouter: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut,) = IViswapPair(getPair(path[i], path[i+1])).getReserves();
            (reserveIn, reserveOut) = path[i] < path[i+1] ? (reserveIn, reserveOut) : (reserveOut, reserveIn);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountOut(uint amountIn, address[] calldata path) public view returns (uint256 amountOut, uint256 priceX96WithImpact, uint256 priceX96WithoutImpact) {
        require(path.length >= 2, 'ViswapRouter: ');
        amountOut = amountIn;
        priceX96WithoutImpact = 1<<96;
        priceX96WithImpact    = 1<<96;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut,) = IViswapPair(getPair(path[i], path[i+1])).getReserves();
            (reserveIn, reserveOut) = path[i] < path[i+1] ? (reserveIn, reserveOut) : (reserveOut, reserveIn);
            amountIn = amountOut;
            amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
            priceX96WithImpact = FullMath.mulDiv(priceX96WithImpact, amountOut, amountIn);
            priceX96WithoutImpact = FullMath.mulDiv(priceX96WithoutImpact, reserveOut, reserveIn);
        }
    }

    //return value: uint256 = uint64 pairId + uint192 balance
    function getLPBalance (address user, uint256 scanLimit, uint256 scanOffset, uint256 resLimit) public view returns(uint256[] memory balances) {
        balances = new uint256[](resLimit);
        uint256 length = IViswapFactory(factory).allPairsLength();
        scanLimit = scanLimit + scanOffset > length ? length : scanLimit + scanOffset;
        length = 0;//reuse length as the length of balances
        for (uint i=scanOffset; i<scanLimit && length<resLimit; i++){
            uint256 balance = IERC20(IViswapFactory(factory).allPairs(i)).balanceOf(user);
            if (balance > 0){
                balances[length] = (i << 192) + balance;
                length ++;
            }
        }
    }

    function getPairInfo (address tokenA, address tokenB) public view
        returns(address pair, uint256 reserve0, uint256 reserve1) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = IViswapFactory(factory).getPair(tokenA, tokenB);
        if (pair != address(0)){
            (reserve0, reserve1,) = IViswapPair(pair).getReserves();
        }
    }




}
