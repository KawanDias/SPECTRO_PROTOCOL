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

    ///////////////
    // FUNCTIONS //
    ///////////////

    function setUp() public {
        spectro = new SpectroCore(beneficiary);
        vm.deal(address(spectro), 100 ether); // Fund the contract for testing
    }

    function test_SucessfulFulfill() public {
        uint256 amount = 1 ether;
        uint256 nonce = 42;
        uint256 initialBalance = solver.balance;

        // Gerando a assinatura dentro do teste
        bytes32 structHash = keccak256(abi.encode(
            keccak256("WithdrawIntent(address solver,uint256 amount,uint256 nonce)"),
            solver,
            amount,
            nonce
        ));
        bytes32 digest = _getEIP712Digest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // -- Execution -- //
        spectro.fullfill(solver, amount, nonce, signature);

        ////////////////////////
        // -- Verification -- //
        ////////////////////////

        // Expected: 1ETH + 0.5% (0.005ETH)
        assertEq(solver.balance, initialBalance + 1.005 ether);
        assertTrue(spectro.usedNonces(nonce));
    }  

    // == REPLAY ATACK TEST == //
    function test_RevertOnReplayAttack() public {
        uint256 amount = 1 ether;
        uint256 nonce = 101;

        bytes32 structHash = keccak256(abi.encode(
            keccak256("WithdrawIntent(address solver,uint256 amount,uint256 nonce)"),
            solver,
            amount,
            nonce
        ));
        bytes32 digest = _getEIP712Digest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First Withdrawal - should succeed
        spectro.fullfill(solver, amount, nonce, signature);

        // Second Withdrawal - should fail and revert
        vm.expectRevert("S.P.E.C.T.R.O: Nonce already used");
        spectro.fullfill(solver, amount, nonce, signature);
    }

    // == FUZZ ATACK TEST == //    
    function test_FuzzFullfillWithRandomAmounts(uint256 randomAmount) public {
        uint256 amount = bound(randomAmount, 0.0001 ether, 10 ether);
        uint256 nonce = uint256(keccak256(abi.encode(randomAmount)));

        bytes32 structHash = keccak256(abi.encode(
            keccak256("WithdrawIntent(address solver,uint256 amount,uint256 nonce)"),
            solver,
            amount,
            nonce
        ));
        bytes32 digest = _getEIP712Digest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(beneficiaryKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 balanceBefore = solver.balance;
        spectro.fullfill(solver, amount, nonce, signature);

        uint256 expectedFee = (amount * spectro.FEE_BPS()) / 10000;
        assertEq(solver.balance, balanceBefore + amount + expectedFee);
    } 

    //////////////////////////////////////
    // Foundry Helper to digest EIP-712 //
    //////////////////////////////////////
    function _getEIP712Digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", spectro.DOMAIN_SEPARATOR(), structHash));
    }
}