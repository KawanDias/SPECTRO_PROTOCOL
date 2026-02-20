// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SpectroCore.sol";

contract SimulateSolver is Script {
   function run() external {
   uint256 signerPrivateKey = vm.envUint("PRIVATE_KEY");
   address receiver = vm.addr(signerPrivateKey);
   SpectroCore spectro = SpectroCore(payable(0x38Ac3bcb71434A68E4c30DCC0b987F97a10Bcd3d));

   SpectroCore.WithdrawalIntent memory intent = SpectroCore.WithdrawalIntent({
      receiver: receiver,
      amount: 0.001 ether,
      fee: 0.0001 ether,
      nonce: 1,
      deadline: block.timestamp + 1 hours,
      targetChainId: 11155111,
      conditionHash: bytes32(0)
   });   

   bytes32 structHash = keccak256(abi.encode(
      spectro.INTENT_TYPEHASH(),
      intent.receiver,
      intent.amount,
      intent.fee,
      intent.nonce,
      intent.deadline,
      intent.targetChainId,
      intent.conditionHash
   ));

   bytes32 digest = spectro.computeDigest(structHash);

   (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
   bytes memory signature = abi.encodePacked(r, s, v);

   vm.startBroadcast(signerPrivateKey);
   spectro.executeIntent(intent, signature);
   vm.stopBroadcast();
  } 
}
