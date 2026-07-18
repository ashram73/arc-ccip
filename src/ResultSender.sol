// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Client, IRouterClient} from "./interfaces/ICCIP.sol";

/**
 * ResultSender — deployed on Arc.
 *
 * A practical CCIP example: something is decided on Arc (a settled market, an
 * oracle result, a finalized vote) and you want other chains to know about it.
 * This contract packages that outcome into a CCIP message and ships it.
 *
 * The pattern generalises. Swap the payload struct and you have cross-chain
 * governance results, cross-chain price attestations, cross-chain state sync —
 * anything where one chain decides and others need to react.
 *
 * Fees are paid in the native gas token, which on Arc means USDC. You quote the
 * fee, you send that exact amount, and any overpayment comes straight back.
 */
contract ResultSender {
    IRouterClient public immutable router;
    address public owner;

    /// The payload we ship across. Keep it small — you pay for calldata size.
    struct Result {
        uint256 marketId;
        string question;
        uint8 winningOutcome;
        uint64 settledAt;
    }

    event ResultBroadcast(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        uint256 marketId,
        uint8 winningOutcome,
        uint256 fee
    );

    error NotOwner();
    error InsufficientFee(uint256 required, uint256 provided);
    error UnsupportedDestination(uint64 chainSelector);
    error RefundFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _router) {
        router = IRouterClient(_router);
        owner = msg.sender;
    }

    // ------------------------------------------------------------- quoting

    /**
     * Always quote before you send. The fee moves with destination gas prices,
     * so a hardcoded value will eventually fail.
     *
     * @param gasLimit gas budgeted for the receiver's ccipReceive() on the
     *        destination. 200_000 is comfortable for a small struct.
     */
    function quote(
        uint64 destinationChainSelector,
        address receiver,
        Result calldata result,
        uint256 gasLimit
    ) public view returns (uint256 fee) {
        return router.getFee(
            destinationChainSelector,
            _buildMessage(receiver, result, gasLimit)
        );
    }

    // ------------------------------------------------------------- sending

    function broadcast(
        uint64 destinationChainSelector,
        address receiver,
        Result calldata result,
        uint256 gasLimit
    ) external payable onlyOwner returns (bytes32 messageId) {
        if (!router.isChainSupported(destinationChainSelector)) {
            revert UnsupportedDestination(destinationChainSelector);
        }

        Client.EVM2AnyMessage memory message =
            _buildMessage(receiver, result, gasLimit);

        uint256 fee = router.getFee(destinationChainSelector, message);
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        // feeToken is address(0), so the fee travels as msg.value.
        messageId = router.ccipSend{value: fee}(destinationChainSelector, message);

        // Send generously, get the difference back. Quotes drift between the
        // moment you read them and the moment you land on-chain.
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            if (!ok) revert RefundFailed();
        }

        emit ResultBroadcast(
            messageId,
            destinationChainSelector,
            receiver,
            result.marketId,
            result.winningOutcome,
            fee
        );
    }

    // ------------------------------------------------------------ internal

    function _buildMessage(
        address receiver,
        Result calldata result,
        uint256 gasLimit
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            // The destination address is abi-encoded, not raw. This trips
            // people up constantly.
            receiver: abi.encode(receiver),
            data: abi.encode(
                result.marketId,
                result.question,
                result.winningOutcome,
                result.settledAt
            ),
            // Empty array = a pure data message, no tokens attached.
            tokenAmounts: new Client.EVMTokenAmount[](0),
            // address(0) = pay in the native gas token.
            feeToken: address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: gasLimit,
                    allowOutOfOrderExecution: true
                })
            )
        });
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// Top up the contract so it can cover fees, or withdraw what's left.
    receive() external payable {}

    function withdraw(address payable to) external onlyOwner {
        (bool ok,) = to.call{value: address(this).balance}("");
        if (!ok) revert RefundFailed();
    }
}
