// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Callee} from "v2-core/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {IFakeLendingProtocol} from "./interfaces/IFakeLendingProtocol.sol";

// This is liquidator contract for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;

    struct CallbackData {
        address repayToken;
        address borrowToken;
        uint256 repayAmount;
        uint256 borrowAmount;
    }

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //
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
        // 5. Decode callbackData
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        // 6. call _FAKE_LENDING_PROTOCOL liquidatePosition
        // 80u -> 1 ether
        // Approve _FAKE_LENDING_PROTOCOL to use borrowToken(weth) borrowAmount(80u)
        IERC20(callbackData.borrowToken).approve(_FAKE_LENDING_PROTOCOL, callbackData.borrowAmount);
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();

        // 7. Deposit ETH to WETH9, 1 ETH -> 1WETH
        // callbackData.repayAmount = 808878247646164300
        IWETH(_WETH9).deposit{value: callbackData.repayAmount}();

        // 8. Repay weth to uniswap pool to get 100u
        // msg.sender = WethUsdcPool
        IWETH(callbackData.repayToken).transfer(msg.sender, callbackData.repayAmount);

        // 9.  Profit can call withdraw to withdraw
        // 1 ETH(1 * 10^18) - 808878247646164300 = 191121752353835700
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        // require(msg.sender==pair)
        // require(sender==address(this))

        require(amountOut > 0, "AmountOut must be greater than 0");

        // 1. Get uniswap pool address
        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);

        // 2. Calculate repay amount: getamountsIn()
        // function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts);
        uint256[] memory amountsIn = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amountOut, path);

        // 3. CallbackData
        // CallbackData{repayToken, borrowToken, repayAmount, borrowAmount}
        CallbackData memory callbackData = CallbackData(path[0], path[1], amountsIn[0], amountOut);

        // 4. Flash swap from uniswap : 80u to this contract & data not empty will execute uniswapV2Call()
        // to -> address(this)
        // function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {}
        // if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        IUniswapV2Pair(pair).swap(0, amountOut, address(this), abi.encode(callbackData));
    }

    receive() external payable {}
}
