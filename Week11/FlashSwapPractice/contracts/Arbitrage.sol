// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Callee} from "v2-core/interfaces/IUniswapV2Callee.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {IUniswapV2Router01} from "v2-periphery/interfaces/IUniswapV2Router01.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //
    struct CallbackData {
        address repayToken;
        address borrowToken;
        uint256 repayAmount;
        uint256 borrowAmount;
        address sushiswap;
        address uniswap;
    }

    event Log(uint256 data);

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Only this contract can call uniswapV2Call");

        // TODO
        // 3. decode callbackdata
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        // 4. calculate how much weth to swap for repayAmount usdc
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(callbackData.sushiswap).getReserves();
        //    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        uint256 amountOut = _getAmountOut(callbackData.borrowAmount, reserve0, reserve1);

        // 5. sushi swap all weth get 543966536 usdc
        IERC20(callbackData.borrowToken).transfer(callbackData.sushiswap, callbackData.borrowAmount);
        IUniswapV2Pair(callbackData.sushiswap).swap(0, amountOut, address(this), "");

        // 6. transfer usdc amountsIn 445781790 to uniswap
        IERC20(callbackData.repayToken).transfer(callbackData.uniswap, callbackData.repayAmount);

        // 7. Profit usdc
        // 543966536 - 445781790 = 98184746
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO
        require(borrowETH > 0, "Borrow amount must be greater than 0");

        // 1. calculate repayAmount usdc
        // token0 is WETH, token1 is USDC

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint256 repayAmount = _getAmountIn(borrowETH, reserve1, reserve0);

        // 2. priceLowerPool swap to get weth & data not empty to execute uniswapV2Call
        address weth = IUniswapV2Pair(priceLowerPool).token0();
        address usdc = IUniswapV2Pair(priceLowerPool).token1();

        CallbackData memory callbackData =
            CallbackData(usdc, weth, repayAmount, borrowETH, priceHigherPool, priceLowerPool);

        // function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data)
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
