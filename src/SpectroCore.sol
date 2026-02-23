// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    uint256 public constant FEE_BPS = 50; // 0.5% Operator fee

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
        // 1. Verify if intent already executed
        bytes32 intentHash = _hashTypedData (keccak256(abi.encode(
            INTENT_TYPEHASH,
            intent.receiver,
            intent.amount,
            intent.fee,
            intent.nonce,
            intent.deadline,
            intent.targetChainId,
            intent.conditionHash
        )));

        require(!executedIntents[intentHash], "Spectro: Intent already executed");
    require(block.timestamp <= intent.deadline, "Spectro: Intent expired");

    // 2. Verify user's signature
    address recoveredUser = ECDSA.recover(intentHash, signature);
    require(recoveredUser == intent.receiver, "Spectro: Invalid signature");

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
        require(block.timestamp <= intent.deadline, "S.P.E.C.T.R.O: Intent expired"); 
        require(!usedNonces[intent.nonce], "S.P.E.C.T.R.O: Nonce already used");

        bytes32 digest = computeDigest(intent);

        address signer = ECDSA.recover(digest, signature);
 
        require(signer == BENEFICIARY, "S.P.E.C.T.R.O: Unauthorized");
        usedNonces[intent.nonce] = true;
        SafeTransferLib.safeTransferETH(intent.receiver, intent.amount);
        if (intent.fee > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, intent.fee);
        }
        emit IntendSettled(msg.sender, signer, intent.amount, intent.fee);
    }

    /**
    * @notice Liquid an intencion for withdrawn presented by an Operator
    * @param solver The address of the Operator who presented the intent
    * @param amount The amount to be withdrawn
    * @param nonce The unique nonce for the intent
    * @param signature The signature of the BENEFICIARY
     */
     function fullfill(
        address solver,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external {
        require(!usedNonces[nonce], "S.P.E.C.T.R.O: Nonce already used");

        // 1. Rebuild intent hash
        bytes32 structHash = keccak256(abi.encode(INTENT_TYPEHASH,solver,amount,nonce));
        bytes32 digest = _hashTypedData(structHash);

        // 2. Verify signature
        if (!BENEFICIARY.isValidSignatureNow(digest, signature)) {
            revert("S.P.E.C.T.R.O: Invalid signature");
        }

        // 3. Mark nonce as used
        usedNonces[nonce] = true;

        // 4. Calculate refund and fee
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 totalRefund = amount + fee;

        // 5. Transfer
        SafeTransferLib.safeTransferETH(solver, totalRefund);

        emit IntendSettled(solver, BENEFICIARY, amount, fee);
    }

    // Receive funds to Vesting
    receive() external payable {}
}