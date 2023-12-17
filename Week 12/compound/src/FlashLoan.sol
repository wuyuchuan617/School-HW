// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {console2} from "../lib/forge-std/src/Test.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CToken} from "../lib/compound-protocol/contracts/CToken.sol";
import {CErc20Delegator} from "../lib/compound-protocol/contracts/CErc20Delegator.sol";
import {
    IFlashLoanSimpleReceiver,
    IPoolAddressesProvider,
    IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams memory params) external returns (uint256 amountOut);
}

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function execute(bytes calldata data) external {
        (,,,, uint256 liquidateAmount) = abi.decode(data, (CErc20Delegator, CErc20Delegator, address, address, uint256));
        // console2.log("5. Get 1250 USDC from AAVE to AaveFlashLoan contract ");
        IPool(address(POOL())).flashLoanSimple(address(this), USDC, liquidateAmount, data, 0);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        (CErc20Delegator cUSDC, CErc20Delegator cUNI, address user1, address user2, uint256 liquidateAmount) =
            abi.decode(params, (CErc20Delegator, CErc20Delegator, address, address, uint256));

        console2.log("liquidateAmount / aaveBorrowAmount: ", liquidateAmount);

        // 執行清算
        // console2.log("6. AaveFlashLoan contract liquidate user1");
        ERC20(USDC).approve(address(cUSDC), liquidateAmount);
        cUSDC.liquidateBorrow(user1, liquidateAmount, cUNI);

        // 把清算後的 cUNI 取出換回 UNI
        uint256 redeemAmount = cUNI.balanceOf(address(this));
        cUNI.redeem(redeemAmount);

        // 把 UNI 換成 USDC
        uint256 swapAmount = ERC20(UNI).balanceOf(address(this));

        // console2.log("7. Swap UNI to USDC");
        console2.log("swapAmount / amountIn: ", swapAmount);
        IERC20(UNI).approve(address(swapRouter), swapAmount);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(UNI),
            tokenOut: address(asset),
            fee: 3000, // 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: redeemAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 amountOut = swapRouter.exactInputSingle(swapParams);
        console2.log("amountOut: ", amountOut);

        // 還 USDC 給 AAVE
        // console2.log("8. RepayBorrow USDC to AAVE");
        uint256 repayBorrorAmount = amount + premium;
        IERC20(asset).approve(address(POOL()), repayBorrorAmount);
        console2.log("repayAVVEBorrorAmount: ", repayBorrorAmount);

        // 把剩下的 USDC 轉給 user2
        // console2.log("9. Transfer profit to user2");
        uint256 profit = amountOut - repayBorrorAmount;
        console2.log("profit: ", profit);
        IERC20(USDC).transfer(user2, profit);

        return true;
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}
