// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ResultSender.sol";

/**
 * Deploy ResultSender on Arc Testnet.
 *
 *   forge script script/DeploySender.s.sol \
 *     --rpc-url https://rpc.testnet.arc.network \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast --legacy --skip-simulation
 *
 * The --skip-simulation flag keeps Foundry from running its pre-broadcast
 * simulation step, which isn't needed here.
 */
contract DeploySender is Script {
    // CCIP Router on Arc Testnet
    address constant ARC_ROUTER = 0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        ResultSender sender = new ResultSender(ARC_ROUTER);
        console.log("ResultSender deployed at:", address(sender));

        vm.stopBroadcast();
    }
}
