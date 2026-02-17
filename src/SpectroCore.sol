// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//////////////////////
// External imports //
//////////////////////
import {EIP712} from "@solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import "./interfaces/ISpectroEvents.sol";

contract  SpectroCore is EIP712, ISpectroEvents{
    using SignatureCheckerLib for address;

    // --- Protocol constants --- //
    bytes32 private constant INTENT_TYPEHASH = 
        keccak256("WithdrawIntent(address solver,uint256 amount,uint256 nonce)");

    uint256 public constant FEE_BPS = 50; // 0.5% Operator fee

    address public immutable BENEFICIARY;
    mapping(uint256 => bool) public usedNonces;

    constructor(address _beneficiary) {
        BENEFICIARY = _beneficiary;
    }

    ///////////////
    // FUNCTIONS //
    ///////////////

    function computeDigest(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedData(structHash);
    }

    // Function fot Solady EIP712 //
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        return ("SPECTRO", "1");
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator();
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
        bytes32 structHash = keccak256(abi.encode(INTENT_TYPEHASH, solver, amount, nonce));
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