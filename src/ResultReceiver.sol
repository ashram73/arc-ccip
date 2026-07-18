// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Client, IAny2EVMMessageReceiver, IERC165} from "./interfaces/ICCIP.sol";

/**
 * ResultReceiver — deployed on the destination chain.
 *
 * Receives outcomes broadcast from Arc and stores them so any contract on this
 * chain can read a result that was decided elsewhere.
 *
 * Three things matter for a safe receiver:
 *
 *   1. Only the router may call ccipReceive(). Without this check, anyone can
 *      forge a message by calling your contract directly.
 *   2. Optionally allowlist the source chain and the sending contract, so you
 *      only trust results from a deployment you control.
 *   3. Never revert on business-logic problems. A revert inside ccipReceive()
 *      marks the message as failed on the lane. Record the failure and move on.
 */
contract ResultReceiver is IAny2EVMMessageReceiver, IERC165 {
    address public immutable router;
    address public owner;

    struct StoredResult {
        bytes32 messageId;
        uint64 sourceChainSelector;
        address sender;
        uint256 marketId;
        string question;
        uint8 winningOutcome;
        uint64 settledAt;
        uint64 receivedAt;
    }

    StoredResult[] private results;

    /// marketId => index+1 in `results` (0 means "not seen")
    mapping(uint256 => uint256) private indexByMarketId;

    /// Optional source filtering. Off by default so the demo works immediately;
    /// switch it on once you know your sender address.
    bool public enforceAllowlists;
    mapping(uint64 => bool) public allowedSourceChain;
    mapping(address => bool) public allowedSender;

    event ResultReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        uint256 marketId,
        uint8 winningOutcome
    );
    event MessageRejected(bytes32 indexed messageId, string reason);

    error NotRouter();
    error NotOwner();

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _router) {
        router = _router;
        owner = msg.sender;
    }

    // ------------------------------------------------------------ receiving

    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        onlyRouter
    {
        address sender = abi.decode(message.sender, (address));

        if (enforceAllowlists) {
            if (!allowedSourceChain[message.sourceChainSelector]) {
                emit MessageRejected(message.messageId, "source chain not allowed");
                return;
            }
            if (!allowedSender[sender]) {
                emit MessageRejected(message.messageId, "sender not allowed");
                return;
            }
        }

        // Decode in exactly the order the sender encoded.
        (
            uint256 marketId,
            string memory question,
            uint8 winningOutcome,
            uint64 settledAt
        ) = abi.decode(message.data, (uint256, string, uint8, uint64));

        results.push(
            StoredResult({
                messageId: message.messageId,
                sourceChainSelector: message.sourceChainSelector,
                sender: sender,
                marketId: marketId,
                question: question,
                winningOutcome: winningOutcome,
                settledAt: settledAt,
                receivedAt: uint64(block.timestamp)
            })
        );
        indexByMarketId[marketId] = results.length;

        emit ResultReceived(
            message.messageId,
            message.sourceChainSelector,
            sender,
            marketId,
            winningOutcome
        );
    }

    // --------------------------------------------------------------- views

    function total() external view returns (uint256) {
        return results.length;
    }

    function getResult(uint256 index) external view returns (StoredResult memory) {
        return results[index];
    }

    function latest() external view returns (StoredResult memory) {
        require(results.length > 0, "nothing received yet");
        return results[results.length - 1];
    }

    /// Look up an outcome by the market id it was decided under on Arc.
    function outcomeOf(uint256 marketId)
        external
        view
        returns (bool found, uint8 winningOutcome, uint64 settledAt)
    {
        uint256 idx = indexByMarketId[marketId];
        if (idx == 0) return (false, 0, 0);
        StoredResult storage r = results[idx - 1];
        return (true, r.winningOutcome, r.settledAt);
    }

    // --------------------------------------------------------------- admin

    function setAllowlistEnforcement(bool on) external onlyOwner {
        enforceAllowlists = on;
    }

    function setAllowedSourceChain(uint64 chainSelector, bool allowed)
        external
        onlyOwner
    {
        allowedSourceChain[chainSelector] = allowed;
    }

    function setAllowedSender(address sender, bool allowed) external onlyOwner {
        allowedSender[sender] = allowed;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // -------------------------------------------------------------- ERC165

    /// Some off-ramp implementations check this before delivering. Advertise
    /// support for both ERC165 and the CCIP receiver interface.
    function supportsInterface(bytes4 interfaceId)
        external
        pure
        override
        returns (bool)
    {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
