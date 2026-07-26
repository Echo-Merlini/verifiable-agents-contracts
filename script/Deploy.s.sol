// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {TruthAnchor} from "../src/TruthAnchor.sol";

/// @notice Deploys TruthAnchor. Run once per chain (mainnet / Base Sepolia / 0G Galileo):
///   forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --private-key $PK --broadcast
contract Deploy is Script {
    function run() external returns (TruthAnchor anchor) {
        vm.startBroadcast();
        anchor = new TruthAnchor();
        vm.stopBroadcast();
    }
}
