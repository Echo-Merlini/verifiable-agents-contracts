// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

/// @title  TruthAnchor — a minimal ERC-8281 (Observation-Commitment) anchor.
/// @author Vértice · trustless-ai
/// @notice "The log is the ledger." Anyone commits a 32-byte digest on-chain; the
///         emitted `Recorded` event *is* the commitment. A verifier reads the event
///         back and recomputes the digest from public data — no trust in this
///         contract, its deployer, or any server is required.
/// @dev    No storage, no owner, no upgrade path — the whole contract is the event.
///         Deployed unchanged to Ethereum mainnet, Base Sepolia, and 0G Galileo (see
///         README). The `/verify` page of the Recomputable Agents demo reads topic1
///         of this event as the committed digest.
///
///         topic0(Recorded) == 0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497
contract TruthAnchor {
    /// @param digest    the 32-byte commitment (e.g. keccak256 of an attestation).
    /// @param committer the address that anchored it (msg.sender).
    event Recorded(bytes32 indexed digest, address indexed committer);

    /// @notice Anchor a digest on-chain.
    /// @dev    Deliberately permissionless and repeatable: the same digest may be
    ///         recorded any number of times (each identical agent action re-commits
    ///         the same digest), and every call emits its own event.
    function record(bytes32 digest) external {
        emit Recorded(digest, msg.sender);
    }
}
