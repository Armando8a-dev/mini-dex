// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/MiniDEX.sol";

contract Deploy is Script {
    // Uniswap V2 on Sepolia
    address constant ROUTER  = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant FACTORY = 0x7E0987E5b3a30e3f2828572Bb659A548460a3003;

    function run() external {
        vm.startBroadcast();
        MiniDEX dex = new MiniDEX(ROUTER, FACTORY);
        console.log("MiniDEX deployed at:", address(dex));
        vm.stopBroadcast();
    }
}
