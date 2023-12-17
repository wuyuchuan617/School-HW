// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../lib/forge-std/src/Script.sol";
import {CErc20Delegator} from "../lib/compound-protocol/contracts/CErc20Delegator.sol";
import {Unitroller} from "../lib/compound-protocol/contracts/Unitroller.sol";
import {ComptrollerG7} from "../lib/compound-protocol/contracts/ComptrollerG7.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Comptroller} from "../lib/compound-protocol/contracts/Comptroller.sol";
import {SimplePriceOracle} from "../lib/compound-protocol/contracts/SimplePriceOracle.sol";
import {WhitePaperInterestRateModel} from "../lib/compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "../lib/compound-protocol/contracts/CErc20Delegate.sol";
import {CToken} from "../lib/compound-protocol/contracts/CToken.sol";

contract AAVEFlashLoanSetup is Script {
    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 uni = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

    Unitroller unitroller;
    Comptroller unitrollerProxy;
    Comptroller comptroller;

    SimplePriceOracle oracle;
    WhitePaperInterestRateModel whitePaperModel;

    CErc20Delegate cERC20_impl;
    CErc20Delegator cUSDC;
    CErc20Delegator cUNI;

    address admin = vm.envAddress("ADMIN");
    uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");

    uint256 private constant BASE = 1e18;

    function run() public virtual {
        vm.startBroadcast(userPrivateKey);
        deployContracts();
        vm.stopBroadcast();
    }

    function deployContracts() internal {
        // deply contract for deploy cToken
        unitroller = new Unitroller();
        comptroller = new Comptroller();
        whitePaperModel = new WhitePaperInterestRateModel(0, 0);
        cERC20_impl = new CErc20Delegate();
        oracle = new SimplePriceOracle();

        // set comptrollerImplementation address
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        unitrollerProxy = Comptroller(address(unitroller));

        // set comptoller oracle
        unitrollerProxy._setPriceOracle(oracle);

        // Deploy cToken contract
        // 使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
        cUSDC = new CErc20Delegator(
            address(usdc),
            unitrollerProxy,
            whitePaperModel,
            10 ** usdc.decimals(),
            "Compound USCD",
            "cUSDC",
            18,
            payable(admin),
            address(cERC20_impl),
            new bytes(0)
        );
        // UNI
        cUNI = new CErc20Delegator(
            address(uni),
            unitrollerProxy,
            whitePaperModel,
            10 ** uni.decimals(),
            "Compound UNI",
            "cUNI",
            18,
            payable(admin),
            address(cERC20_impl),
            new bytes(0)
        );

        // Support markets
        unitrollerProxy._supportMarket(CToken(address(cUSDC)));
        unitrollerProxy._supportMarket(CToken(address(cUNI)));

        // 在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $5
        oracle.setDirectPrice(address(usdc), 1 * 10 ** (36 - usdc.decimals()));
        oracle.setDirectPrice(address(uni), 5 * 10 ** (36 - uni.decimals()));

        // 設定 UNI 的 collateral factor 為 50%
        unitrollerProxy._setCollateralFactor(CToken(address(cUNI)), 0.5 * 1e18);

        // Liquidation incentive 設為 8% (1.08 * 1e18)
        unitrollerProxy._setLiquidationIncentive(1.08 * 1e18);

        // Set closing factor
        unitrollerProxy._setCloseFactor(0.5 * 1e18);
    }
}
