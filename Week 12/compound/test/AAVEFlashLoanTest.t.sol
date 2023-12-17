// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "../lib/forge-std/src/Test.sol";
import {AAVEFlashLoanSetup} from "../script/AAVEFlashLoanSetup.s.sol";
import {CToken} from "../lib/compound-protocol/contracts/CToken.sol";
import {CErc20Delegator} from "../lib/compound-protocol/contracts/CErc20Delegator.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    IFlashLoanSimpleReceiver,
    IPoolAddressesProvider,
    IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import {AaveFlashLoan} from "../src/FlashLoan.sol";

contract AAVEFlashLoanTest is Test, AAVEFlashLoanSetup {
    address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    address user1;
    address user2;

    function setUp() public {
        // Fork Ethereum mainnet at block 17465000
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc);
        vm.rollFork(17_465_000);

        deployContracts();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        deal(address(uni), user1, 1000 * 10 ** uni.decimals());
        deal(address(usdc), user2, 2500 * 10 ** usdc.decimals());
    }

    function testAAVELiquidate() public {
        // mint 2500 顆 USDC for borrow
        vm.startPrank(user2);

        uint256 mintAmount = 2500 * 10 ** usdc.decimals();
        usdc.approve(address(cUSDC), mintAmount);
        cUSDC.mint(mintAmount);

        vm.stopPrank();

        vm.startPrank(user1);
        // console2.log("1. User1 mint 1000 UNI as collateral");
        // Supply mint 一顆 token B
        // User1 使用 1000 顆 UNI 作為抵押品借出 2500 顆 USDC
        uint256 collteralAmount = 1000 * 10 ** uni.decimals();
        uni.approve(address(cUNI), collteralAmount);
        cUNI.mint(collteralAmount);

        // Enter market
        address[] memory collateralToken = new address[](1);
        collateralToken[0] = address(cUNI);
        unitrollerProxy.enterMarkets(collateralToken);

        // Borrow USDC
        // console2.log("2. User1 borrow 2500 USDC");
        uint256 borrowAmount = 2500 * 10 ** usdc.decimals();
        (uint256 errCode) = cUSDC.borrow(borrowAmount);
        require(errCode == 0, "Borrow fail!");

        assertEq(usdc.balanceOf(user1), borrowAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        // console2.log("3. Admin set UNI price from $5 to $4");
        // 將 UNI 價格改為 $4 使 User1 產生 Shortfall
        oracle.setUnderlyingPrice(CToken(address(cUNI)), 4 * 10 ** (36 - uni.decimals()));
        console2.log("UNI Price: ", oracle.getUnderlyingPrice(CToken(address(cUNI))));
        vm.stopPrank();

        // 並讓 User2 透過 AAVE 的 Flash loan 來借錢清算 User1
        // 債物: 2500
        // 抵押: 1000 * 4 * 0.5 = 2000

        vm.startPrank(user2);

        // 算最多可還數量 2500 * 0.5 = 1250
        uint256 borrowBalance = cUSDC.borrowBalanceCurrent(user1);
        uint256 closeFactorMantissa = unitrollerProxy.closeFactorMantissa();
        uint256 maxLiquidateAmount = borrowBalance * closeFactorMantissa / 1e18;

        // user2 去 AAVE flashLoanSimple 借 1250 usdc
        // console2.log("4. User2 flashloan 1250 USDC from AAVE");
        AaveFlashLoan aaveFlashLoan = new AaveFlashLoan();
        bytes memory params =
            abi.encode(CErc20Delegator(cUSDC), CErc20Delegator(cUNI), user1, user2, maxLiquidateAmount);
        aaveFlashLoan.execute(params);

        // 可以自行檢查清算 50% 後是不是大約可以賺 63 USDC
        assertGe(usdc.balanceOf(user2), 63 * 10 ** usdc.decimals());
        assertEq(usdc.balanceOf(user2), 63638693);

        vm.stopPrank();
    }
}
