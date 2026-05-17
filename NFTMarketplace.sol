// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
        uint256 listedAt;
    }

    struct Offer {
        uint256 offerId;
        uint256 listingId;
        address buyer;
        uint256 amount;
        uint256 expiresAt;
        bool active;
        uint256 createdAt;
    }

    // State variables
    uint256 private _listingIdCounter;
    uint256 private _offerIdCounter;
    uint256 public marketplaceFee = 250; // 2.5% in basis points
    address public feeRecipient;

    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer) public offers;
    mapping(address => mapping(uint256 => uint256)) public tokenToListing; // nftContract => tokenId => listingId
    mapping(address => uint256[]) public sellerListings;
    mapping(address => uint256[]) public buyerOffers;
    mapping(uint256 => uint256[]) public listingOffers; // listingId => offerIds[]

    // Events
    event ItemListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );

    event ItemSold(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    event ListingCancelled(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller
    );

    event OfferMade(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        uint256 expiresAt
    );

    event OfferAccepted(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        uint256 amount
    );

    event OfferCancelled(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer
    );

    event PriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice
    );

    constructor(
        address _feeRecipient,
        address _initialOwner
    ) Ownable(_initialOwner) {
        feeRecipient = _feeRecipient;
        _listingIdCounter = 1;
        _offerIdCounter = 1;
    }

    // List an NFT for sale
    function listItem(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not the owner"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
                IERC721(nftContract).getApproved(tokenId) == address(this),
            "Not approved"
        );
        require(tokenToListing[nftContract][tokenId] == 0, "Already listed");

        uint256 listingId = _listingIdCounter++;

        listings[listingId] = Listing({
            listingId: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true,
            listedAt: block.timestamp
        });

        tokenToListing[nftContract][tokenId] = listingId;
        sellerListings[msg.sender].push(listingId);

        emit ItemListed(listingId, nftContract, tokenId, msg.sender, price);
    }

    // Buy an NFT directly
    function buyItem(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own item");

        // Verify ownership and approval
        require(
            IERC721(listing.nftContract).ownerOf(listing.tokenId) ==
                listing.seller,
            "Seller no longer owns NFT"
        );

        listing.active = false;
        tokenToListing[listing.nftContract][listing.tokenId] = 0;

        // Calculate fees
        uint256 fee = (listing.price * marketplaceFee) / 10000;
        uint256 sellerAmount = listing.price - fee;

        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        // Transfer payments
        if (fee > 0) {
            payable(feeRecipient).transfer(fee);
        }
        payable(listing.seller).transfer(sellerAmount);

        // Refund excess payment
        if (msg.value > listing.price) {
            payable(msg.sender).transfer(msg.value - listing.price);
        }

        // Cancel all offers for this listing
        _cancelAllOffers(listingId);

        emit ItemSold(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller,
            msg.sender,
            listing.price
        );
    }

    // Cancel a listing
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.active, "Listing not active");

        listing.active = false;
        tokenToListing[listing.nftContract][listing.tokenId] = 0;

        // Cancel all offers for this listing
        _cancelAllOffers(listingId);

        emit ListingCancelled(
            listingId,
            listing.nftContract,
            listing.tokenId,
            msg.sender
        );
    }

    // Update listing price
    function updatePrice(uint256 listingId, uint256 newPrice) external {
        require(newPrice > 0, "Price must be greater than 0");
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.active, "Listing not active");

        uint256 oldPrice = listing.price;
        listing.price = newPrice;

        emit PriceUpdated(listingId, oldPrice, newPrice);
    }

    // Make an offer on a listing
    function makeOffer(
        uint256 listingId,
        uint256 expiresAt
    ) external payable nonReentrant {
        require(msg.value > 0, "Offer must be greater than 0");
        require(
            expiresAt > block.timestamp,
            "Expiration must be in the future"
        );

        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.sender != listing.seller, "Cannot offer on your own item");

        uint256 offerId = _offerIdCounter++;

        offers[offerId] = Offer({
            offerId: offerId,
            listingId: listingId,
            buyer: msg.sender,
            amount: msg.value,
            expiresAt: expiresAt,
            active: true,
            createdAt: block.timestamp
        });

        buyerOffers[msg.sender].push(offerId);
        listingOffers[listingId].push(offerId);

        emit OfferMade(offerId, listingId, msg.sender, msg.value, expiresAt);
    }

    // Accept an offer
    function acceptOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");

        Listing storage listing = listings[offer.listingId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.active, "Listing not active");

        // Verify ownership
        require(
            IERC721(listing.nftContract).ownerOf(listing.tokenId) == msg.sender,
            "No longer own NFT"
        );

        offer.active = false;
        listing.active = false;
        tokenToListing[listing.nftContract][listing.tokenId] = 0;

        // Calculate fees
        uint256 fee = (offer.amount * marketplaceFee) / 10000;
        uint256 sellerAmount = offer.amount - fee;

        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(
            msg.sender,
            offer.buyer,
            listing.tokenId
        );

        // Transfer payments
        if (fee > 0) {
            payable(feeRecipient).transfer(fee);
        }
        payable(msg.sender).transfer(sellerAmount);

        // Cancel all other offers for this listing
        _cancelAllOffers(offer.listingId);

        emit OfferAccepted(
            offerId,
            offer.listingId,
            offer.buyer,
            msg.sender,
            offer.amount
        );
        emit ItemSold(
            listing.listingId,
            listing.nftContract,
            listing.tokenId,
            msg.sender,
            offer.buyer,
            offer.amount
        );
    }

    // Cancel an offer
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.buyer == msg.sender, "Not the buyer");
        require(offer.active, "Offer not active");

        offer.active = false;

        // Refund the buyer
        payable(msg.sender).transfer(offer.amount);

        emit OfferCancelled(offerId, offer.listingId, msg.sender);
    }

    // Internal function to cancel all offers for a listing
    function _cancelAllOffers(uint256 listingId) internal {
        uint256[] memory offerIds = listingOffers[listingId];
        for (uint256 i = 0; i < offerIds.length; i++) {
            Offer storage offer = offers[offerIds[i]];
            if (offer.active) {
                offer.active = false;
                payable(offer.buyer).transfer(offer.amount);
                emit OfferCancelled(offerIds[i], listingId, offer.buyer);
            }
        }
    }

    // View functions
    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getActiveListings() external view returns (Listing[] memory) {
        uint256 activeCount = 0;

        // Count active listings
        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }

        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 index = 0;

        // Populate active listings
        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (listings[i].active) {
                activeListings[index] = listings[i];
                index++;
            }
        }

        return activeListings;
    }

    function getListingsByCollection(
        address nftContract
    ) external view returns (Listing[] memory) {
        uint256 collectionCount = 0;

        // Count listings for this collection
        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (listings[i].active && listings[i].nftContract == nftContract) {
                collectionCount++;
            }
        }

        Listing[] memory collectionListings = new Listing[](collectionCount);
        uint256 index = 0;

        // Populate collection listings
        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (listings[i].active && listings[i].nftContract == nftContract) {
                collectionListings[index] = listings[i];
                index++;
            }
        }

        return collectionListings;
    }

    function getSellerListings(
        address seller
    ) external view returns (Listing[] memory) {
        uint256[] memory listingIds = sellerListings[seller];
        uint256 activeCount = 0;

        // Count active listings
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (listings[listingIds[i]].active) {
                activeCount++;
            }
        }

        Listing[] memory activeSellerListings = new Listing[](activeCount);
        uint256 index = 0;

        // Populate active listings
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (listings[listingIds[i]].active) {
                activeSellerListings[index] = listings[listingIds[i]];
                index++;
            }
        }

        return activeSellerListings;
    }

    function getListingOffers(
        uint256 listingId
    ) external view returns (Offer[] memory) {
        uint256[] memory offerIds = listingOffers[listingId];
        uint256 activeCount = 0;

        // Count active offers
        for (uint256 i = 0; i < offerIds.length; i++) {
            if (
                offers[offerIds[i]].active &&
                block.timestamp <= offers[offerIds[i]].expiresAt
            ) {
                activeCount++;
            }
        }

        Offer[] memory activeOffers = new Offer[](activeCount);
        uint256 index = 0;

        // Populate active offers
        for (uint256 i = 0; i < offerIds.length; i++) {
            if (
                offers[offerIds[i]].active &&
                block.timestamp <= offers[offerIds[i]].expiresAt
            ) {
                activeOffers[index] = offers[offerIds[i]];
                index++;
            }
        }

        return activeOffers;
    }

    function getBuyerOffers(
        address buyer
    ) external view returns (Offer[] memory) {
        uint256[] memory offerIds = buyerOffers[buyer];
        uint256 activeCount = 0;

        // Count active offers
        for (uint256 i = 0; i < offerIds.length; i++) {
            if (
                offers[offerIds[i]].active &&
                block.timestamp <= offers[offerIds[i]].expiresAt
            ) {
                activeCount++;
            }
        }

        Offer[] memory activeOffers = new Offer[](activeCount);
        uint256 index = 0;

        // Populate active offers
        for (uint256 i = 0; i < offerIds.length; i++) {
            if (
                offers[offerIds[i]].active &&
                block.timestamp <= offers[offerIds[i]].expiresAt
            ) {
                activeOffers[index] = offers[offerIds[i]];
                index++;
            }
        }

        return activeOffers;
    }

    // Admin functions
    function setMarketplaceFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee cannot exceed 10%"); // Max 10%
        marketplaceFee = _fee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid address");
        feeRecipient = _feeRecipient;
    }

    function withdrawFees() external onlyOwner {
        payable(feeRecipient).transfer(address(this).balance);
    }

    // Emergency function to cancel expired offers
    function cleanupExpiredOffers(uint256[] calldata offerIds) external {
        for (uint256 i = 0; i < offerIds.length; i++) {
            Offer storage offer = offers[offerIds[i]];
            if (offer.active && block.timestamp > offer.expiresAt) {
                offer.active = false;
                payable(offer.buyer).transfer(offer.amount);
                emit OfferCancelled(offerIds[i], offer.listingId, offer.buyer);
            }
        }
    }
}
