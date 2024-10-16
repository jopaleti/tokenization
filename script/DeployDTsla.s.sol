// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {dTSLA} from "../src/dTSLA.sol";
import {console2} from "forge-std/console2.sol";

contract DeployDTsla is Script {
    string constant alpacaMintSource = "./functions/sources/alpacaBalance.js";
    string constant alpacaRedeemSource = "";
    uint64 constant subId = 3657;

    function run() public {
        string memory mintSource = vm.readFile(alpacaMintSource);
        vm.startBroadcast();
        dTSLA dTsla = new dTSLA(subId, alpacaRedeemSource);
        dTsla.setMintSource(mintSource);
        vm.stopBroadcast();
        console2.log(address(dTsla));
    }
}