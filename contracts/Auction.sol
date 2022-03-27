// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "hardhat/console.sol";

contract Auction {
    address payable public beneficiary;
    uint256 public auctionEndTime = block.timestamp + 500;
    address nftContractAddress;
    uint256 tokenId;

    // Current state of the auction.
    address public highestBidder;
    uint256 public highestBid;

    // Allowed withdrawals of previous bids
    mapping(address => uint256) pendingReturns;

    // Set to true at the end, disallows any change.
    // By default initialized to `false`.
    bool ended;

    // Events that will be emitted on changes.
    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    // Errors that describe failures.

    // The triple-slash comments are so-called natspec
    // comments. They will be shown when the user
    // is asked to confirm a transaction or
    // when an error is displayed.

    /// The auction has already ended.
    error AuctionAlreadyEnded();
    /// There is already a higher or equal bid.
    error BidNotHighEnough(uint256 highestBid);
    /// The auction has not ended yet.
    error AuctionNotYetEnded();
    /// The function auctionEnd has already been called.
    error AuctionEndAlreadyCalled();

    // // Mapping from token ID to approved address
    // mapping(uint256 => address) private _tokenApprovals;

    // /**
    //  * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
    //  */
    // event Approval(
    //     address indexed owner,
    //     address indexed approved,
    //     uint256 indexed tokenId
    // );

    // function approve(address to) public virtual {
    //     address owner = IERC721(nftContractAddress).ownerOf(tokenId);
    //     require(to != owner, "ERC721: approval to current owner");

    //     require(
    //         msg.sender == owner,
    //         "ERC721: approve caller is not owner nor approved for all"
    //     );

    //     _approve(to);
    // }

    // /**
    //  * @dev Approve `to` to operate on `tokenId`
    //  *
    //  * Emits a {Approval} event.
    //  */
    // function _approve(address to) internal virtual {
    //     _tokenApprovals[tokenId] = to;
    //     emit Approval(
    //         IERC721(nftContractAddress).ownerOf(tokenId),
    //         to,
    //         tokenId
    //     );
    // }

    /*╔══════════════════════════════╗
      ║  TRANSFER NFTS TO CONTRACT   ║
      ╚══════════════════════════════╝*/
    function transferNftToAuctionContract() public {
        if (IERC721(nftContractAddress).ownerOf(tokenId) == beneficiary) {
            IERC721(nftContractAddress).approve(address(this),tokenId);
            IERC721(nftContractAddress).transferFrom(
                beneficiary,
                address(this),
                tokenId
            );
            require(
                IERC721(nftContractAddress).ownerOf(tokenId) == address(this),
                "nft transfer failed"
            );
        } else {
            require(
                IERC721(nftContractAddress).ownerOf(tokenId) == address(this),
                "Seller doesn't own NFT"
            );
        }
    }

    function transferNftToHighestBidder() internal {
        if (IERC721(nftContractAddress).ownerOf(tokenId) == address(this)) {
            IERC721(nftContractAddress).transferFrom(
                address(this),
                highestBidder,
                tokenId
            );
            require(
                IERC721(nftContractAddress).ownerOf(tokenId) == highestBidder,
                "nft transfer failed"
            );
        } else {
            require(
                IERC721(nftContractAddress).ownerOf(tokenId) == address(this),
                "Contract doesn't own NFT"
            );
        }
    }

    /// beneficiary address `beneficiaryAddress`.
    constructor(
        // ---------------------- Change Biding time -------------------------
        address payable beneficiaryAddress,
        address _nftContractAddress,
        uint256 _tokenId
    ) {
        beneficiary = beneficiaryAddress;
        nftContractAddress = _nftContractAddress;
        tokenId = _tokenId;
    }

    /// Bid on the auction with the value sent
    /// together with this transaction.
    /// The value will only be refunded if the
    /// auction is not won.
    function bid() external payable {
        // No arguments are necessary, all
        // information is already part of
        // the transaction. The keyword payable
        // is required for the function to
        // be able to receive Ether.

        // Revert the call if the bidding
        // period is over.
        if (block.timestamp > auctionEndTime) revert AuctionAlreadyEnded();

        // If the bid is not higher, send the
        // money back (the revert statement
        // will revert all changes in this
        // function execution including
        // it having received the money).
        if (msg.value <= highestBid) revert BidNotHighEnough(highestBid);

        if (highestBid != 0) {
            // Sending back the money by simply using
            // highestBidder.send(highestBid) is a security risk
            // because it could execute an untrusted contract.
            // It is always safer to let the recipients
            // withdraw their money themselves.

            // Can use ----- Superfluid to send back returns -----
            pendingReturns[highestBidder] += highestBid;
        }
        highestBidder = msg.sender;
        highestBid = msg.value;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    /// Withdraw a bid that was overbid.
    function withdraw() external returns (bool) {
        uint256 amount = pendingReturns[msg.sender];
        if (amount > 0) {
            // It is important to set this to zero because the recipient
            // can call this function again as part of the receiving call
            // before `send` returns.
            pendingReturns[msg.sender] = 0;

            // msg.sender is not of type `address payable` and must be
            // explicitly converted using `payable(msg.sender)` in order
            // use the member function `send()`.
            if (!payable(msg.sender).send(amount)) {
                // No need to call throw here, just reset the amount owing
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    /// End the auction and send the highest bid
    /// to the beneficiary.
    function auctionEnd() external {
        // It is a good guideline to structure functions that interact
        // with other contracts (i.e. they call functions or send Ether)
        // into three phases:
        // 1. checking conditions
        // 2. performing actions (potentially changing conditions)
        // 3. interacting with other contracts
        // If these phases are mixed up, the other contract could call
        // back into the current contract and modify the state or cause
        // effects (ether payout) to be performed multiple times.
        // If functions called internally include interaction with external
        // contracts, they also have to be considered interaction with
        // external contracts.

        // 1. Conditions
        if (block.timestamp < auctionEndTime) revert AuctionNotYetEnded();
        if (ended) revert AuctionEndAlreadyCalled();

        // 2. Effects
        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        // 3. Interaction
        beneficiary.transfer(highestBid);

        transferNftToHighestBidder();
    }
}
