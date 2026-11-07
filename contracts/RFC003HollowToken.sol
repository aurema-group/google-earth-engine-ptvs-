// SPDX-License-Identifier: Apache-2.0
// PTVS v1.0 Reference Implementation. 
// Protected by Zenodo DOI: 10.5281/zenodo.24001234 & Safe Creative Reg: 2611067566842
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RFC-003 Hollow Token Protocol
 * @notice Implements the Layer-0 physical circuit breaker for RWA tokenization under PTVS v1.0.
 * @dev When a physical anomaly is detected (via GEE-PTVS Oracle or Legal Mandate), 
 *      the token enters a "Hollow" state where transfers are paused, protecting the liquidity pool.
 */
contract RFC003HollowToken is ERC20, Ownable {
    
    // --- STATE VARIABLES ---
    
    /// @notice Address of the authorized PTVS Oracle (e.g., GEE-PTVS automated script or PTCE multisig)
    address public ptvsOracle;
    
    /// @notice The SHA-256 hash of the last valid Canonical QFER (Satellite or Forensic Report)
    bytes32 public lastVerifiedQFERHash;
    
    /// @notice Timestamp of the last successful physical verification
    uint256 public lastVerificationTimestamp;
    
    /// @notice Maximum allowed time (in seconds) between physical verifications (e.g., 90 days)
    uint256 public constant MAX_VERIFICATION_INTERVAL = 90 days;
    
    /// @notice CRITICAL: If true, the asset has failed physical/legal checks. The token is "Hollow".
    bool public isHollowTokenActive;
    
    /// @notice Reason for the current freeze (IPFS hash or legal document reference)
    string public freezeReasonURI;

    // --- EVENTS ---
    
    event OracleUpdated(address indexed newOracle);
    event PhysicalStatusVerified(bytes32 indexed qferHash, uint256 timestamp, bool anomalyDetected);
    event HollowTokenActivated(string reasonURI, uint256 timestamp);
    event HollowTokenDeactivated(bytes32 newQferHash, uint256 timestamp);

    // --- MODIFIERS ---

    /// @dev Restricts functions to the authorized PTVS Oracle
    modifier onlyOracle() {
        require(msg.sender == ptvsOracle, "RFC003: Caller is not the PTVS Oracle");
        _;
    }

    /**
     * @dev The Core PTVS v1.0 Modifier. 
     * Ensures the asset is physically sound and legally bound before allowing transfers.
     */
    modifier isPhysicallyAndLegallyBound() {
        require(!isHollowTokenActive, "RFC003: Token is HOLLOW. Transfers frozen due to physical/legal anomaly.");
        require(
            block.timestamp <= lastVerificationTimestamp + MAX_VERIFICATION_INTERVAL, 
            "RFC003: Physical verification expired. Update QFER required."
        );
        _;
    }

    // --- CONSTRUCTOR ---

    constructor(
        string memory name_, 
        string memory symbol_, 
        address initialOracle_,
        bytes32 initialQFERHash_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(initialOracle_ != address(0), "RFC003: Oracle cannot be zero address");
        ptvsOracle = initialOracle_;
        lastVerifiedQFERHash = initialQFERHash_;
        lastVerificationTimestamp = block.timestamp;
    }

    // --- ORACLE & CIRCUIT BREAKER FUNCTIONS ---

    /**
     * @notice Receives the cryptographic proof from the GEE-PTVS Oracle or PTCE Expert.
     * @param _qferHash The SHA-256 hash of the Canonical JSON report.
     * @param _anomalyDetected Boolean flag from the oracle indicating structural/environmental failure.
     * @param _reasonURI Link to the full forensic report (IPFS/Arweave).
     */
    function receiveOracleReport(
        bytes32 _qferHash, 
        bool _anomalyDetected, 
        string calldata _reasonURI
    ) external onlyOracle {
        lastVerifiedQFERHash = _qferHash;
        lastVerificationTimestamp = block.timestamp;
        
        emit PhysicalStatusVerified(_qferHash, block.timestamp, _anomalyDetected);

        if (_anomalyDetected) {
            _activateHollowToken(_reasonURI);
        } else if (isHollowTokenActive) {
            // If anomaly is resolved and new report is clean
            _deactivateHollowToken();
        }
    }

    /**
     * @notice Allows the owner (Legal/Multisig) to manually freeze the asset via legal mandate.
     * @param _legalHash Hash of the court order or arbitral award.
     * @param _reasonURI Link to the legal document.
     */
    function freezeByLegalMandate(bytes32 _legalHash, string calldata _reasonURI) external onlyOwner {
        lastVerifiedQFERHash = _legalHash;
        _activateHollowToken(_reasonURI);
    }

    // --- INTERNAL LOGIC ---

    function _activateHollowToken(string memory _reasonURI) internal {
        isHollowTokenActive = true;
        freezeReasonURI = _reasonURI;
        emit HollowTokenActivated(_reasonURI, block.timestamp);
    }

    function _deactivateHollowToken() internal {
        isHollowTokenActive = false;
        freezeReasonURI = "";
        emit HollowTokenDeactivated(lastVerifiedQFERHash, block.timestamp);
    }

    // --- ERC20 OVERRIDES ---

    function transfer(address to, uint256 amount) public override isPhysicallyAndLegallyBound returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override isPhysicallyAndLegallyBound returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    // --- ADMIN FUNCTIONS ---

    function setOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "RFC003: Oracle cannot be zero address");
        ptvsOracle = _newOracle;
        emit OracleUpdated(_newOracle);
    }
}
