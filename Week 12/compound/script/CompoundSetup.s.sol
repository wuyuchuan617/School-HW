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

contract UnderlyingToken is ERC20 {
    constructor() ERC20("MY Token", "MTK") {}
}

contract TokenA is ERC20 {
    constructor() ERC20("Token A", "TKA") {}
}

contract TokenB is ERC20 {
    constructor() ERC20("Token B", "TKB") {}
}

contract CompoundSetup is Script {
    ERC20 tokenA;
    ERC20 tokenB;
    ERC20 underlying;
    Unitroller unitroller;
    Comptroller unitrollerProxy;
    Comptroller comptroller;
    SimplePriceOracle oracle;
    WhitePaperInterestRateModel whitePaperModel;
    CErc20Delegate cERC20_impl;
    CErc20Delegator cToken;
    CErc20Delegator cTokenA;
    CErc20Delegator cTokenB;

    address admin = vm.envAddress("ADMIN");
    uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");

    uint256 private constant BASE = 1e18;

    function run() public virtual {
        vm.startBroadcast(userPrivateKey);
        deployContracts();
        vm.stopBroadcast();
    }

    function deployContracts() internal {
        tokenA = new TokenA();
        tokenB = new TokenB();

        // deply contract for deploy cToken
        underlying = new UnderlyingToken();
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
        cToken = new CErc20Delegator(
            address(underlying),
            unitrollerProxy,
            whitePaperModel,
            1e18,
            "Compound My Token",
            "cMTK",
            18,
            payable(admin),
            address(cERC20_impl),
            new bytes(0)
        );

        cTokenA = new CErc20Delegator(
            address(tokenA),
            unitrollerProxy,
            whitePaperModel,
            1e18,
            "Compound TokenA",
            "cTKA",
            18,
            payable(admin),
            address(cERC20_impl),
            new bytes(0)
        );

        cTokenB = new CErc20Delegator(
            address(tokenB),
            unitrollerProxy,
            whitePaperModel,
            1e18,
            "Compound TokenB",
            "cTKB",
            18,
            payable(admin),
            address(cERC20_impl),
            new bytes(0)
        );

        // Support markets
        unitrollerProxy._supportMarket(CToken(address(cToken)));
        unitrollerProxy._supportMarket(CToken(address(cTokenA)));
        unitrollerProxy._supportMarket(CToken(address(cTokenB)));

        // Set cTokens price
        // 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
        oracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);
        oracle.setUnderlyingPrice(CToken(address(cTokenB)), 100e18);

        // collateralFactorMantissa, scaled by 1e18
        // Set tokenB collateral factor
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 0.5 * 1e18);

        // Set closing factor
        unitrollerProxy._setCloseFactor(0.5 * 1e18);
    }
}
