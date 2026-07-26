// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {TruthAnchor} from "../src/TruthAnchor.sol";

contract TruthAnchorTest is Test {
    TruthAnchor anchor;
    event Recorded(bytes32 indexed digest, address indexed committer);

    function setUp() public {
        anchor = new TruthAnchor();
    }

    /// The event carries the exact digest + committer a verifier reads back.
    function test_EmitsRecorded() public {
        bytes32 d = keccak256("i think its working now my bad"); // the showcase query
        vm.expectEmit(true, true, false, false);
        emit Recorded(d, address(this));
        anchor.record(d);
    }

    /// The same digest may be anchored repeatedly — every identical agent action
    /// re-commits the same digest, and each call is a valid independent anchor.
    function test_SameDigestMayRepeat() public {
        bytes32 d = bytes32(uint256(1));
        anchor.record(d);
        anchor.record(d);
    }

    /// topic0 is the canonical Recorded(bytes32,address) signature the subgraph +
    /// the /verify RPC read both key off of.
    function test_Topic0IsCanonical() public pure {
        assertEq(
            keccak256("Recorded(bytes32,address)"),
            0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497
        );
    }

    function testFuzz_AnyDigest(bytes32 d) public {
        vm.expectEmit(true, true, false, false);
        emit Recorded(d, address(this));
        anchor.record(d);
    }
}
