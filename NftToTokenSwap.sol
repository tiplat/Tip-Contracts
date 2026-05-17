// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract NftToTokenSwap is IERC721Receiver, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC721 public immutable nft;
    IERC20 public immutable token;

   
    uint256 public constant TIER1_MAX = 1_000;
    uint256 public constant TIER2_MAX = 3_000;
    uint256 public constant TIER3_MAX = 7_000;
    uint256 public constant TIER4_MAX = 10_000;

    uint256 public constant TIER1_REWARD = 50000000 ether;
    uint256 public constant TIER2_REWARD = 45000000 ether;
    uint256 public constant TIER3_REWARD = 35000000 ether;
    uint256 public constant TIER4_REWARD = 25000000 ether;

    uint256 public constant MAX_BATCH_SIZE = 10;

    event Swapped(address indexed user, uint256 indexed tokenId, uint256 amount);
    event BatchSwapped(address indexed user, uint256 count, uint256 totalAmount);
    event NftWithdrawn(uint256 indexed tokenId, address indexed to);
    event TokenWithdrawn(address indexed to, uint256 amount);

    error UnsupportedNft();
    error InsufficientPool();
    error TokenIdOutOfRange(uint256 tokenId);
    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 maxAllowed);

    constructor(address _nft, address _token, address _owner) Ownable(_owner) {
        nft = IERC721(_nft);
        token = IERC20(_token);
    }

    function rewardFor(uint256 tokenId) public pure returns (uint256) {
        if (tokenId <= TIER1_MAX) return TIER1_REWARD;
        if (tokenId <= TIER2_MAX) return TIER2_REWARD;
        if (tokenId <= TIER3_MAX) return TIER3_REWARD;
        if (tokenId <= TIER4_MAX) return TIER4_REWARD;
        revert TokenIdOutOfRange(tokenId);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        whenNotPaused
        nonReentrant
        returns (bytes4)
    {
        if (msg.sender != address(nft)) revert UnsupportedNft();

        uint256 reward = rewardFor(tokenId);
        if (token.balanceOf(address(this)) < reward) revert InsufficientPool();

        emit Swapped(from, tokenId, reward);
        token.safeTransfer(from, reward);

        return IERC721Receiver.onERC721Received.selector;
    }

   
    function batchSwap(uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 n = tokenIds.length;
        if (n == 0) revert EmptyBatch();
        if (n > MAX_BATCH_SIZE) revert BatchTooLarge(n, MAX_BATCH_SIZE);

        uint256 totalReward = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 reward = rewardFor(tokenId); 
            totalReward += reward;
            emit Swapped(msg.sender, tokenId, reward);
            nft.transferFrom(msg.sender, address(this), tokenId);
        }

        if (token.balanceOf(address(this)) < totalReward) revert InsufficientPool();

        emit BatchSwapped(msg.sender, n, totalReward);
        token.safeTransfer(msg.sender, totalReward);
    }

  
    function previewBatchReward(uint256[] calldata tokenIds)
        external
        pure
        returns (uint256 total)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            total += rewardFor(tokenIds[i]);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        emit TokenWithdrawn(to, amount);
        token.safeTransfer(to, amount);
    }

    function withdrawNft(uint256 tokenId, address to) external onlyOwner {
        emit NftWithdrawn(tokenId, to);
        nft.safeTransferFrom(address(this), to, tokenId);
    }
}
