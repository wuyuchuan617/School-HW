// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.17;

import {Script} from "forge-std/Script.sol";
import {SimpleSwap} from "../contracts/SimpleSwap.sol";
import {TestERC20} from "../contracts/test/TestERC20.sol";

contract SimpleSwapScript is Script {
    TestERC20 public tokenA;
    TestERC20 public tokenB;

    function run() external {
        vm.startBroadcast(0x2eaf5652603b370dac51f5633adbc43106e32ff075451be14bcdaf1b2999d91b);
        tokenB = new TestERC20("token B", "TKB");
        tokenA = new TestERC20("token A", "TKA");
        SimpleSwap simpleSwap = new SimpleSwap(address(tokenA), address(tokenB));
        vm.stopBroadcast();
    }
}
