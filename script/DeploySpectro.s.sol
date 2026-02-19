// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SpectroCore.sol";

contract DeploySpectro is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = 0x538037D600696Dfb7F02BFDdafDdD747afca83e1;

        vm.startBroadcast(deployerPrivateKey);

        new SpectroCore(initialOwner);

        vm.stopBroadcast();
    }
}