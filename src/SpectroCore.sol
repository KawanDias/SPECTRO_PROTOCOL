// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


///////////////////
// Custom Errors //
///////////////////

error Unauthorized();
error InvalidSignature();
error NonceAlreadyUsed(uint256 nonce);
error IntentExpired();
error ConditionNotProven(bytes32 hash);
error ETHTransferFailed(); 
error IntentAlreadyExecuted();

//////////////////////
// External imports //
//////////////////////

import {Ownable} from "@solady/auth/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import "./interfaces/ISpectroEvents.sol";

contract  SpectroCore is EIP712, ISpectroEvents, Ownable{
    using SignatureCheckerLib for address;
    using SafeTransferLib for address;
    using ECDSA for bytes32;

    // --- Protocol constants --- //
    bytes32 public constant INTENT_TYPEHASH = 
        keccak256("WithdrawalIntent(address receiver,uint256 amount,uint256 fee,uint256 nonce,uint256 deadline,uint256 targetChainId,bytes32 conditionHash)");

    address public immutable BENEFICIARY;
    mapping(uint256 => bool) public usedNonces;

    constructor(address _beneficiary) {
        _initializeOwner(msg.sender); 
        BENEFICIARY = _beneficiary;
    }

    //////////////
    // MAPPINGS //
    //////////////

    // Intention hash for execution status
    mapping(bytes32 => bool) public executedIntents;


    // Mapping to store conditions already proved by oracles
    mapping(bytes32 => bool) public provenConditions;

  
    ////////////
    // EVENTS //
    ////////////

    // event to monitore when a conditions is valid
    event ConditionProven(bytes32 indexed conditionHash);


    /////////////
    // STRUCTS //
    /////////////

struct WithdrawalIntent {
    address receiver;
    uint256 amount;
    uint256 fee;
    uint256 nonce;
    uint256 deadline;
    uint256 targetChainId;
    bytes32 conditionHash;
}
    ///////////////
    // FUNCTIONS //
    ///////////////

    function _transferFunds(address to, uint256 amount) internal {
        to.safeTransferETH(amount);
    } 

  function computeDigest(WithdrawalIntent memory intent) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            INTENT_TYPEHASH,
            intent.receiver,
            intent.amount,
            intent.fee,
            intent.nonce,
            intent.deadline,
            intent.targetChainId,
            intent.conditionHash
        ));
        return _hashTypedData(structHash);
    }

    // Function fot Solady EIP712 //
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        return ("SPECTRO", "1");
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator();
    }

    // -- function for cross-chain intents execution -- //
    function executeCrossChainIntent(
        WithdrawalIntent calldata intent,
        bytes calldata signature,
        bytes32 proofOfPayment // ID transation on another chain
    ) external {

        bytes32 intentHash = computeDigest(intent);
        

    if (executedIntents[intentHash]) {
        revert IntentAlreadyExecuted();
    }

    if (block.timestamp > intent.deadline) {
        revert IntentExpired();
    }

    // 2. Verify user's signature
    address recoveredUser = ECDSA.recover(intentHash, signature);
    if (recoveredUser != intent.receiver) {
        revert InvalidSignature();
    }

    // 3. Mark as executed before any state changes to prevent reentrancy
    executedIntents[intentHash] = true;

    // 4. Reward Logic 
    // contract releases funds that were "trapped" in the source network to Solver
    _transferFunds(msg.sender, intent.amount);

    emit IntentFulfilled(intent.receiver, msg.sender, intent.amount, intent.targetChainId, intent.conditionHash);
    } 

    function executeIntent(
        WithdrawalIntent calldata intent,
        bytes calldata signature
    ) external {
        // Deadline verification
        if (block.timestamp > intent.deadline) {
            revert IntentExpired();
        }

        // Replay verification
        if (usedNonces[intent.nonce]) {
            revert NonceAlreadyUsed(intent.nonce);
        }

        // Digest and signer recover
        bytes32 digest = computeDigest(intent);
        address signer = ECDSA.recover(digest, signature);

        // condition cross chain verification
        if (intent.conditionHash != bytes32(0)) {
            if (!provenConditions[intent.conditionHash]) {
                revert ConditionNotProven(intent.conditionHash);
            }
        }

    // auth and verification
    if (signer != BENEFICIARY) {
        revert Unauthorized();
    }

    // execution and tranfers
    usedNonces[intent.nonce] = true;
    
    SafeTransferLib.safeTransferETH(intent.receiver, intent.amount);
    
    if (intent.fee > 0) {
        SafeTransferLib.safeTransferETH(msg.sender, intent.fee);
    }

    emit IntendSettled(msg.sender, signer, intent.amount, intent.fee);
}       

    // Temporary function to simulate getting the cross-chain proof 
    function fulfillCondition(bytes32 conditionHash) external {
        provenConditions[conditionHash] = true;
        emit ConditionProven(conditionHash);
    }

    // Receive funds to Vesting
    receive() external payable {}
}