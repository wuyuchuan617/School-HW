// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISimpleSwap} from "./interface/ISimpleSwap.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    address public tokenA;
    address public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

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

    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        // 1. 檢查 amountAIn & amountBIn 必須大於零
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // 2. 按 Pool 兩個 token 比例計算加入的 amountA, amountB
        (amountA, amountB) = _addLiquidity(amountAIn, amountBIn);

        // 3. 將 amountA, amountB transfer 到合約中
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // 4. Mint LP tokens 給 LP (msg.sender)
        liquidity = _mintLpToken(msg.sender, amountA, amountB);
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external override returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        // 1. LP (msg.sender) transfer LP token to this contract
        _transfer(msg.sender, address(this), liquidity);

        // 2. Burn LP token & 計算要轉多少 tokenA, tokenB back to LP
        (amountA, amountB) = _burnLpToken();

        // 3. Transfer tokenA, tokenB back to LP (msg.sender)
        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        // 4. update balance to reserve
        _update();
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external override returns (uint256 amountOut) {
        // 1. 檢查 param
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // 2. 將 amountIn transfer 到 this contract
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // 3. 計算 amountOut
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == tokenA ? (reserveA, reserveB) : (reserveB, reserveA);
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);

        // 4. 將 amountOut transfer 給 msg.sender
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        ERC20(tokenOut).transfer(msg.sender, amountOut);

        // 5. 檢查 K 值
        uint256 balanceA = ERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = ERC20(tokenB).balanceOf(address(this));
        require(balanceA * balanceB >= reserveA * reserveB, "SimpleSwap: K");

        // 6. update
        _update();

        // 7. Emit event: Swap
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function getTokenA() external view override returns (address token0) {
        token0 = tokenA;
    }

    function getTokenB() external view override returns (address token1) {
        token1 = tokenB;
    }

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = reserveA;
        reserve1 = reserveB;
    }

    function _update() internal {
        // 把 tokenA, tokenB balance 更新到 reserveA, reserveB
        reserveA = IERC20(tokenA).balanceOf(address(this));
        reserveB = IERC20(tokenB).balanceOf(address(this));
    }

    function _mintLpToken(address to, uint256 amountA, uint256 amountB) internal returns (uint256 liquidity) {
        // 1. 計算要 mint 多少 LP token
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB);
        } else {
            liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
        }

        // 2. Mint LP token 給 LP (msg.sender)
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        // 3. 把 tokenA, tokenB balance 更新到 reserveA, reserveB
        _update();
        return (liquidity);
    }

    function _burnLpToken() internal returns (uint256 amountA, uint256 amountB) {
        // 1. 計算要轉多少 tokenA, tokenB back to LP
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));
        uint256 totalSupply = totalSupply();

        amountA = (liquidity * (balanceA)) / totalSupply;
        amountB = (liquidity * (balanceB)) / totalSupply;

        // 2. Burn LP token
        require(amountA > 0 && amountB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        return (amountA, amountB);
    }

    function _addLiquidity(uint256 amountADesired, uint256 amountBDesired)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        // 1-1. amountADesired 為零代表初次加入流動性 amountADesired, amountBDesired 可決定 Pool 比例
        // 1-2. totalSupply() 不為零則必須按 Pool 比例加入流動性
        if (totalSupply() == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 2. 計算 amountADesired 可加入多少 tokenB (amountBOptimal)
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);

            // 3-1. 如果可加入的 amountBOptimal 小於 amountBDesire 則加入 amountBOptimal 數量
            // 3-2. 如果可加入的 amountBOptimal 大於 amountBDesire，則需改為用固定 amountBDesired 來計算可加入多少 tokenＡ(amountAOptimal)
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
        return (amountA, amountB);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function _quote(uint256 amountA, uint256 reserve0, uint256 reserve1) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(reserve0 > 0 && reserve1 > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserve1) / reserve0;
    }
}
