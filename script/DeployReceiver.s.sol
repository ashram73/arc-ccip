// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ResultReceiver.sol";

/**
 * Deploy ResultReceiver on the destination chain (Ethereum Sepolia).
 *
 *   forge script script/DeployReceiver.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 *
 * Pass the router of whichever chain you're deploying to via ROUTER, or leave
 * it unset to use the Sepolia default below.
 */
contract DeployReceiver is Script {
    // CCIP Router on Ethereum Sepolia
    address constant SEPOLIA_ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address router = vm.envOr("ROUTER", SEPOLIA_ROUTER);

        vm.startBroadcast(pk);

        ResultReceiver receiver = new ResultReceiver(router);
        console.log("ResultReceiver deployed at:", address(receiver));
        console.log("Using router:", router);

        vm.stopBroadcast();
    }
}
