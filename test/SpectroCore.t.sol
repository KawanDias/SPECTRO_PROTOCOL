// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/////////////
// imports //
/////////////
import "forge-std/Test.sol";
import "../src/SpectroCore.sol";

contract SpectroCoreTeste is Test {
    SpectroCore spectro;

    // Set up the test environment //
    uint256 beneficiaryKey = 0xA11CE; // Patrick's private key
    address beneficiary = vm.addr(beneficiaryKey);
    address solver = address(0xB0B); // Operator's address
    address user = address(0x123);


    ///////////////
    // FUNCTIONS //
    ///////////////

    function setUp() public {
        spectro = new SpectroCore(beneficiary);
        vm.deal(address(spectro), 100 ether); // Fund the contract for testing
    }

    function test_SucessfulExecuteIntent() public {
        SpectroCore.WithdrawalIntent memory intent = SpectroCore.WithdrawalIntent({
            receiver: user,
            amount: 1 ether,
            fee: 0.1 ether,
            nonce: 1,
            deadline: block.timestamp + 1 hours,
            targetChainId: block.chainid,
            conditionHash: bytes32(0)
        });

        // Agora o computeDigest aceita a struct 'intent' diretamente
        bytes32 digest = spectro.computeDigest(intent);

        // Assina (usando a chave do BENEFICIARY definido no setUp)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execução
        vm.prank(solver);
        spectro.executeIntent(intent, signature);

        // Verificação
        assertEq(user.balance, 1 ether);
        assertTrue(spectro.usedNonces(1));
    }

    // == REPLAY ATACK TEST == //
   function test_RevertOnReplayAttack() public {
    // 1. Defina a intenção usando a Struct
    SpectroCore.WithdrawalIntent memory intent = SpectroCore.WithdrawalIntent({
        receiver: user,
        amount: 1 ether,
        fee: 0.1 ether,
        nonce: 101, 
        deadline: block.timestamp + 1 hours,
        targetChainId: block.chainid,
        conditionHash: bytes32(0)
    });

    // Generate digest and Signature
    bytes32 digest = spectro.computeDigest(intent);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    // First Execution - may pass
    vm.prank(solver);
    spectro.executeIntent(intent, signature);

    // Second Execution - may fail
    vm.expectRevert("S.P.E.C.T.R.O: Nonce already used");
    vm.prank(solver);
    spectro.executeIntent(intent, signature);
}

    // == FUZZ ATACK TEST == //    
    function test_FuzzFullfillWithRandomAmounts(uint256 randomAmount) public {
    uint256 amount = bound(randomAmount, 0.001 ether, 10 ether);
    uint256 nonce = uint256(keccak256(abi.encode(randomAmount)));

    // Random value struct
    SpectroCore.WithdrawalIntent memory intent = SpectroCore.WithdrawalIntent({
        receiver: user,
        amount: amount,
        fee: (amount * spectro.FEE_BPS()) / 10000,
        nonce: nonce,
        deadline: block.timestamp + 1 hours,
        targetChainId: block.chainid,
        conditionHash: bytes32(0)
    });

    // Generate digest and signature
    bytes32 digest = spectro.computeDigest(intent);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    // Execution & Verification
    uint256 balanceBefore = user.balance;
    vm.prank(solver);
    spectro.executeIntent(intent, signature);

    assertEq(user.balance, balanceBefore + amount);
}

    //////////////////////////////////////
    // Foundry Helper to digest EIP-712 //
    //////////////////////////////////////
    function _getEIP712Digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", spectro.DOMAIN_SEPARATOR(), structHash));
    }
}