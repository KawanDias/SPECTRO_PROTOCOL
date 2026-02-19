// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SpectroCore.sol";

contract SimulateSolver is Script {
   function run() external {
    uint256 ownerPK = vm.envUint("PRIVATE_KEY");
    address solver = vm.addr(ownerPK);

    SpectroCore spectro = SpectroCore(payable(0xa4EAB60D6aB09A43f59B0BFb97F806523Ac412cD));

    uint256 amount = 0.001 ether;
    uint256 nonce = 1; 

    console.log("Generating signature EIP-712 for interoperability...");

    bytes32 structHash = keccak256(abi.encode(
                keccak256("WithdrawIntent(address solver,uint256 amount,uint256 nonce)"),
                solver,
                amount,
                nonce
            ));
            bytes32 digest = spectro.computeDigest(structHash);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, digest);
            bytes memory signature = abi.encodePacked(r, s, v);

            vm.startBroadcast(ownerPK);
            spectro.executeIntent(solver, amount, nonce, signature);
            vm.stopBroadcast();

            console.log("Success! Solver executed the intent without cost for the user.");
   }
}
