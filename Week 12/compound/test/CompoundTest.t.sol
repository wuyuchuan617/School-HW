// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {CompoundSetup} from "../script/CompoundSetup.s.sol";
import {CToken} from "../lib/compound-protocol/contracts/CToken.sol";

contract CompoundTestScript is Test, CompoundSetup {
    address user1;
    address user2;

    uint256 initialBalance = 100 * 1e18;

    function setUp() public {
        deployContracts();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        deal(address(tokenA), user1, initialBalance); //
        deal(address(tokenA), user2, initialBalance);
        deal(address(tokenB), user1, initialBalance); //
        deal(address(tokenB), user2, initialBalance);
    }

    // mint & redeem
    // User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token
    // 再用 100 cERC20 token redeem 回 100 顆 ERC20
    function testMintRedeem() public {
        vm.startPrank(user1);

        // Mint
        tokenA.approve(address(cTokenA), tokenA.balanceOf(user1));
        cTokenA.mint(tokenA.balanceOf(user1));

        assertEq(tokenA.balanceOf(user1), 0);
        assertEq(cTokenA.balanceOf(user1), initialBalance);

        // Redeem
        cTokenA.redeem(cTokenA.balanceOf(user1));

        assertEq(tokenA.balanceOf(user1), initialBalance);
        assertEq(cTokenA.balanceOf(user1), 0);

        vm.stopPrank();
    }

    // 3. 讓 User1 borrow/repay
    function testBorrow() public {
        // mint cTokenA for borrow
        vm.startPrank(user2);

        uint256 mintAmount = 50 * 10 ** tokenA.decimals();
        tokenA.approve(address(cTokenA), mintAmount);
        cTokenA.mint(mintAmount);

        vm.stopPrank();

        vm.startPrank(user1);

        // Supply mint 一顆 token B
        uint256 collteralAmount = 1 * 10 ** tokenB.decimals();
        tokenB.approve(address(cTokenB), collteralAmount);
        cTokenB.mint(collteralAmount);

        // Enter market
        address[] memory collateralToken = new address[](1);
        collateralToken[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(collateralToken);

        // Borrow
        uint256 borrowAmount = 50 * 10 ** tokenA.decimals();
        (uint256 errCode) = cTokenA.borrow(borrowAmount);
        require(errCode == 0, "Borrow fail!");

        assertEq(tokenA.balanceOf(user1), initialBalance + borrowAmount);

        vm.stopPrank();
    }

    function testRepay() public {
        testBorrow();

        vm.startPrank(user1);

        uint256 borrowAmount = 50 * 10 ** tokenA.decimals();

        tokenA.approve(address(cTokenA), borrowAmount);
        (uint256 errCode) = cTokenA.repayBorrow(borrowAmount);
        require(errCode == 0, "Borrow fail!");

        assertEq(tokenA.balanceOf(user1), initialBalance);

        vm.stopPrank();
    }

    function _liquidate() internal {
        vm.startPrank(user2);
        
        uint256 closeFactorMantissa = unitrollerProxy.closeFactorMantissa();

        // 算最多課還數量
        uint256 borrowBalance = cTokenA.borrowBalanceCurrent(user1);
        uint256 maxLiquidateAmount = borrowBalance * closeFactorMantissa / 1e18;

        // The amount of the borrowed asset to be repaid and converted into collateral,
        // specified in units of the underlying borrowed asset.
        tokenA.approve(address(cTokenA), maxLiquidateAmount);
        cTokenA.liquidateBorrow(user1, maxLiquidateAmount, cTokenB);

        vm.stopPrank();
    }

    // 調整 token B 的 collateral factor，讓 User1 被 User2 清算
    function testLiquidateCollateralFactor() public {
        testBorrow();

        // collateral factor 改為 40%
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 0.4 * 1e18);
        (, uint256 collateralFactorMantissaB,) = unitrollerProxy.markets(address(cTokenB));
        console2.log("Collateral factor: ", collateralFactorMantissaB / 1e16, "%");

        // Check account liquidity
        (uint256 err, uint256 liquidity, uint256 shortfall) = unitrollerProxy.getAccountLiquidity(user1);
        console2.log("User1 shortfall:  ", shortfall);
        assertEq(shortfall, 10e18);

        _liquidate();

        // Check account liquidity
        (err, liquidity, shortfall) = unitrollerProxy.getAccountLiquidity(user1);
        console2.log("User1 liquidity:  ", liquidity);
        assertEq(liquidity, 15e18);
    }

    // 調整 oracle 中 token B 的價格，讓 User1 被 User2 清算
    function testLiquidatePrice() public {
        testBorrow();

        // token B 的價格為 $100 -> $80
        oracle.setUnderlyingPrice(CToken(address(cTokenB)), 8e19);
        console2.log("Underlying Price: ", oracle.getUnderlyingPrice(CToken(address(cTokenB))));

        // Check account liquidity
        // 抵押：1 * 80 * 0.5 = 40 * 10e18
        (uint256 err, uint256 liquidity, uint256 shortfall) = unitrollerProxy.getAccountLiquidity(user1);
        console2.log("User1 shortfall:  ", shortfall);
        assertEq(shortfall, 10e18);

        _liquidate();

        // Check account liquidity
        (err, liquidity, shortfall) = unitrollerProxy.getAccountLiquidity(user1);
        console2.log("User1 liquidity:  ", liquidity);
        assertEq(liquidity, 15e18);
    }
}
