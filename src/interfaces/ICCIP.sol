// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Minimal, self-contained CCIP interfaces.
 *
 * These mirror the official `@chainlink/contracts-ccip` types. They're inlined
 * here so this repo compiles with zero external dependencies — handy when you
 * just want to read the code and understand the shape of a CCIP message.
 *
 * In production you'd normally import the real package:
 *   import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
 *   import {Client}        from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
 *   import {CCIPReceiver}  from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
 */

library Client {
    /// A token + amount pair. Left empty for pure data messages.
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    /// What you send: the outbound message.
    struct EVM2AnyMessage {
        bytes receiver;                 // abi.encode(destination contract address)
        bytes data;                     // your arbitrary payload
        EVMTokenAmount[] tokenAmounts;  // empty array = data-only message
        address feeToken;               // address(0) = pay the fee in the native gas token
        bytes extraArgs;                // encoded execution options (see below)
    }

    /// What you receive: the inbound message, delivered by the router.
    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;                   // abi.decode(sender, (address))
        bytes data;
        EVMTokenAmount[] destTokenAmounts;
    }

    /// Tag prefixed to v2 execution options.
    bytes4 public constant GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;

    /**
     * Execution options for the destination chain.
     * - gasLimit: gas budgeted for your receiver's ccipReceive() call. Too low
     *   and delivery fails; too high and you overpay the fee.
     * - allowOutOfOrderExecution: lets messages execute independently of each
     *   other rather than strictly in sequence. Required on v1.6 lanes.
     */
    struct EVMExtraArgsV2 {
        uint256 gasLimit;
        bool allowOutOfOrderExecution;
    }

    function _argsToBytes(EVMExtraArgsV2 memory extraArgs)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(GENERIC_EXTRA_ARGS_V2_TAG, extraArgs);
    }
}

/// The CCIP Router — your single entry point for sending.
interface IRouterClient {
    /// Quote the fee before sending. Always call this first.
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    /// Send the message. Pay `fee` as msg.value when feeToken is address(0).
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32 messageId);

    /// Is there an outbound lane to this destination?
    function isChainSupported(uint64 destChainSelector) external view returns (bool);
}

/// Implement this on the destination chain to receive messages.
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
