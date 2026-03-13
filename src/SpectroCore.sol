// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


    // ==================================================
    // Imports
    // ==================================================

    import {Ownable} from "@solady/auth/Ownable.sol";
    import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
    import {EIP712} from "@solady/utils/EIP712.sol";
    import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";
    import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
    import "./interfaces/ISpectroEvents.sol";

    // ==================================================
    // Errors
    // ==================================================

    error Unauthorized();
    error InvalidSignature();
    error NonceAlreadyUsed(uint256 nonce);
    error IntentExpired();
    error ConditionNotProven(bytes32 hash);
    error ETHTransferFailed(); 
    error IntentAlreadyExecuted();


    // ==================================================
    // Interfaces
    // ==================================================

        // -- none

    // ==================================================
    // Libraries
    // ==================================================

        // -- none

    // ==================================================
    // Structs
    // ==================================================

    struct WithdrawalIntent {
            address receiver;
            uint256 amount;
            uint256 fee;
            uint256 nonce;
            uint256 deadline;
            uint256 targetChainId;
            bytes32 conditionHash;
        }


    // ==================================================
    // Enums
    // ==================================================

        // -- none

    // ==================================================
    // Storage / State Variables
    // ==================================================

    contract  SpectroCore is EIP712, ISpectroEvents, Ownable{
        using SignatureCheckerLib for address;
        using SafeTransferLib for address;
        using ECDSA for bytes32;

        // --- Protocol constants --- //
        bytes32 public constant INTENT_TYPEHASH = 
            keccak256("WithdrawalIntent(address receiver,uint256 amount,uint256 fee,uint256 nonce,uint256 deadline,uint256 targetChainId,bytes32 conditionHash)");

            


        address public immutable BENEFICIARY;

        // -- Mappings -- //
        mapping(uint256 => bool) public usedNonces;

        // Intention hash for execution status
        mapping(bytes32 => bool) public executedIntents;

        // Mapping to store conditions already proved by oracles
        mapping(bytes32 => bool) public provenConditions;



    // ==================================================
    // Events
    // ==================================================

            // event to monitore when a conditions is valid
            event ConditionProven(bytes32 indexed conditionHash);

    // ==================================================
    // Modifiers
    // ==================================================

    // -- none

    // ==================================================
    // Constructor
    // ==================================================

        constructor(address _beneficiary) {
            _initializeOwner(msg.sender); 
            BENEFICIARY = _beneficiary;
        }

    // ==================================================
    // External Functions
    // ==================================================

    // -- function for cross-chain intents execution -- //
        function executeCrossChainIntent(
                WithdrawalIntent calldata intent,
                bytes calldata signature,
                bytes32 proofOfPayment // ID transation on another chain
       ) external {

            if (block.timestamp > intent.deadline) {
                revert IntentExpired();
            }    

            if (proofOfPayment != intent.conditionHash) {
                revert ConditionNotProven(proofOfPayment);
            }

            // Cross-chain proof verification
            if(!provenConditions[proofOfPayment]){
                revert ConditionNotProven(proofOfPayment);
            } 

            bytes32 intentHash = computeDigest(intent);
            
                if (executedIntents[intentHash]) {
                revert IntentAlreadyExecuted();
            }

            // Signature verification
            address recoveredUser = ECDSA.recover(intentHash, signature);
            if (recoveredUser != intent.receiver) {
                revert InvalidSignature();
            }  
            
            // Mark as executed
            executedIntents[intentHash] = true;

            // Reward solver
            _transferFunds(msg.sender, intent.amount);

            emit IntentFulfilled(
                intent.receiver,
                msg.sender,
                intent.amount,
                intent.targetChainId,
                intent.conditionHash
            );
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
        function fulfillCondition(bytes32 conditionHash) external onlyOwner {
            provenConditions[conditionHash] = true;
            emit ConditionProven(conditionHash);
        }

    // ==================================================
    // Public Functions
    // ==================================================

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

        function DOMAIN_SEPARATOR() public view returns (bytes32) {
            return _domainSeparator();
        }


    // ==================================================
    // Internal Functions
    // ==================================================

    function _transferFunds(address to, uint256 amount) internal {
            to.safeTransferETH(amount);
        } 

        // Function fot Solady EIP712 //
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
            return ("SPECTRO", "1");
        }

    // ==================================================
    // Private Functions
    // ==================================================

        // -- none

    // ==================================================
    // View / Pure Helpers
    // ==================================================

        // -- none

    // ==================================================
    // Receive / Fallback
    // ==================================================

        receive() external payable {}

}