// SPDX-License-Identifier: GPL 3.0
pragma solidity 0.8.19;

import {Script, console} from "@forge-std/Script.sol";
import {Vester} from "src/Vester.sol";
import {Factory} from "src/Factory.sol";

address constant MAXIS_OPS = address(0x166f54F44F271407f24AA1BE415a730035637325);
address constant SD_BAL_GAUGE = address(0x3E8C72655e48591d93e6dfdA16823dB0fF23d859);
address constant VOTING_REWARDS_MERKLE_STASH = address(0x03E34b085C52985F6a5D27243F20C84bDdc01Db4);

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Vester vester = new Vester(bytes32("sdbal.eth"), SD_BAL_GAUGE, VOTING_REWARDS_MERKLE_STASH);
        Factory factory = new Factory(address(vester), MAXIS_OPS);

        vm.stopBroadcast();
    }
}
