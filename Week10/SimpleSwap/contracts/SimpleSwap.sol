// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISimpleSwap} from "./interface/ISimpleSwap.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    address public tokenA;
    address public tokenB;

    uint256 private reservesA; // uses single storage slot, accessible via getReserves
    uint256 private reservesB; // uses single storage slot, accessible via getReserves

    event TokenSwap(address indexed sender, uint256 amountIn, uint256 amountOut);

    constructor(address _tokenA, address _tokenB) ERC20("LP Token", "LP") {
        require(_tokenA.code.length > 0, "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(_tokenB.code.length > 0, "SimpleSwap: TOKENB_IS_NOT_CONTRACT");

        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");

        if (_tokenA < _tokenB) {
            tokenA = _tokenA;
            tokenB = _tokenB;
        } else {
            tokenA = _tokenB;
            tokenB = _tokenA;
        }
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external override returns (uint256 amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");

        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESSES");

        IERC20 tokenInContract = IERC20(tokenIn);
        IERC20 tokenOutContract = IERC20(tokenOut);

        tokenInContract.transferFrom(msg.sender, address(this), amountIn);

        uint256 balanceIn = tokenIn == address(tokenA) ? reservesA : reservesB;
        uint256 balanceOut = tokenIn == address(tokenA) ? reservesB : reservesA;

        amountOut = (balanceIn * amountIn) / balanceOut;

        tokenOutContract.transfer(msg.sender, amountOut);

        if (tokenIn == tokenA) {
            reservesA = reservesA + amountIn;
            reservesB = reservesB - amountOut;
        } else {
            reservesB = reservesB + amountIn;
            reservesA = reservesA - amountOut;
        }

        // swap
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // Mint LP tokens
        // (uint112 _reservesA, uint112 _reservesB,) = getReserves(reservesA, reservesB); // gas savings
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        uint256 amountA = balanceA - reservesA;
        uint256 amountB = balanceB - reservesB;

        uint256 _totalSupply = totalSupply();

        // Mint LP tokens
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amountA * _totalSupply / reservesA, amountB * _totalSupply / reservesB);
        }

        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(msg.sender, liquidity);

        // Update reserves
        reservesA = reservesA + amountAIn;
        reservesB = reservesB + amountBIn;

        // Transfer tokens to contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountAIn);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBIn);

        emit AddLiquidity(msg.sender, amountAIn, amountBIn, liquidity);
        return (amountAIn, amountBIn, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external override returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // Sender LP token to contract
        this.transferFrom(msg.sender, address(this), liquidity);

        // Calculate amounts
        uint256 totalSupply = totalSupply();

        amountA = (reservesA * liquidity) / totalSupply;
        amountB = (reservesB * liquidity) / totalSupply;

        // Update reserves
        reservesA = reservesA - amountA;
        reservesB = reservesB - amountB;

        // Burn LP tokens
        _burn(msg.sender, liquidity);

        // Transfer tokens out
        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function getReserves() external view override returns (uint256 reserveA, uint256 reserveB) {
        return (reservesA, reservesB);
    }

    function getTokenA() external view override returns (address _tokenA) {
        return tokenA;
    }

    function getTokenB() external view override returns (address _tokenB) {
        return tokenB;
    }
}
