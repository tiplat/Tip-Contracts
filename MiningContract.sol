// =========================================
/*
████████╗██╗██████╗
╚══██╔══╝██║██╔══██╗
   ██║   ██║██████╔╝     $TIP Tokens Mining
   ██║   ██║██╔═══╝    
   ██║   ██║██║          https://tip.lat
   ╚═╝   ╚═╝╚═╝
*/
// =========================================


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MiningContract
 * @notice NFT tokenId-based token mining.
 */
contract MiningContract is ReentrancyGuard, Ownable, Pausable {

    // ─── Immutables ───────────────────────────────────────────────────────────

    IERC20  public immutable rewardToken;
    IERC721 public immutable nftCollection;

    uint256 public immutable REWARD_AMOUNT;

    uint256 public immutable REWARD_DURATION;

    // ─── Structs ───────────────────────────────────────────────────────────────

    struct TokenMinerInfo {
        address miner;          // wallet that started this mining session
        uint256 startTime;      // block.timestamp when mining began
        uint256 claimedAmount;  // tokens already transferred out (wei)
        bool    active;         // true while session is in progress
        bool    completed;      // PERMANENT — true once full allocation claimed
    }

    mapping(uint256 => TokenMinerInfo) public tokenMiners;

  
    mapping(address => uint256) public walletActiveTokenId;

    mapping(address => bool) public walletHasActiveMining;

    // ─── Events ───────────────────────────────────────────────────────────────

    event MiningStarted(address indexed user, uint256 indexed tokenId, uint256 startTime);
    event RewardsClaimed(address indexed user, uint256 indexed tokenId, uint256 amount, uint256 totalClaimed);
    event MiningCompleted(address indexed user, uint256 indexed tokenId, uint256 totalClaimed);
    event SessionForfeited(address indexed previousMiner, uint256 indexed tokenId);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(
        address _rewardToken,
        address _nftCollection,
        uint256 _rewardAmount,
        uint256 _rewardDuration
    ) Ownable(msg.sender) {
        require(_rewardToken   != address(0), "MiningContract: zero reward token");
        require(_nftCollection != address(0), "MiningContract: zero NFT collection");
        require(_rewardAmount  > 0,           "MiningContract: zero reward amount");
        require(_rewardDuration > 0,          "MiningContract: zero reward duration");

        rewardToken    = IERC20(_rewardToken);
        nftCollection  = IERC721(_nftCollection);
        REWARD_AMOUNT  = _rewardAmount;
        REWARD_DURATION = _rewardDuration;
    }

    // ─── Core mining logic ────────────────────────────────────────────────────

  
    function startMining(uint256 tokenId) external whenNotPaused nonReentrant {
        require(
            nftCollection.ownerOf(tokenId) == msg.sender,
            "MiningContract: caller does not own this NFT"
        );

        TokenMinerInfo storage info = tokenMiners[tokenId];

        require(!info.completed, "MiningContract: allocation already completed for this NFT");

        if (info.active && info.miner != msg.sender) {
            address prevMiner = info.miner;
            walletHasActiveMining[prevMiner] = false;
            info.active        = false;
            info.startTime     = 0;
            info.claimedAmount = 0;
            info.miner         = address(0);
            emit SessionForfeited(prevMiner, tokenId);
        }

        require(!info.active, "MiningContract: this NFT is already actively mining");

        require(
            !walletHasActiveMining[msg.sender],
            "MiningContract: wallet already has an active mining session"
        );

        require(
            rewardToken.balanceOf(address(this)) >= REWARD_AMOUNT,
            "MiningContract: contract underfunded - contact the owner"
        );

        info.miner         = msg.sender;
        info.startTime     = block.timestamp;
        info.claimedAmount = 0;
        info.active        = true;

        walletActiveTokenId[msg.sender]  = tokenId;
        walletHasActiveMining[msg.sender] = true;

        emit MiningStarted(msg.sender, tokenId, block.timestamp);
    }

 
    function claimRewards() external whenNotPaused nonReentrant {
        require(walletHasActiveMining[msg.sender], "MiningContract: no active mining session");

        uint256 tokenId = walletActiveTokenId[msg.sender];
        TokenMinerInfo storage info = tokenMiners[tokenId];

        require(
            nftCollection.ownerOf(tokenId) == msg.sender,
            "MiningContract: must still own the NFT to claim rewards"
        );

        uint256 claimable = _pendingRewards(info);
        require(claimable > 0, "MiningContract: no rewards available to claim");

        info.claimedAmount += claimable;

        bool done = (block.timestamp >= info.startTime + REWARD_DURATION)
                 || (info.claimedAmount >= REWARD_AMOUNT);

        if (done) {
            if (info.claimedAmount > REWARD_AMOUNT) {
                claimable -= (info.claimedAmount - REWARD_AMOUNT);
                info.claimedAmount = REWARD_AMOUNT;
            }
            info.active    = false;
            info.completed = true;
            walletHasActiveMining[msg.sender] = false;

            emit MiningCompleted(msg.sender, tokenId, info.claimedAmount);
        }

        // ── 5. Transfer tokens ────────────────────────────────────────────────
        require(
            rewardToken.transfer(msg.sender, claimable),
            "MiningContract: token transfer failed"
        );

        emit RewardsClaimed(msg.sender, tokenId, claimable, info.claimedAmount);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    function pendingRewards(address user) external view returns (uint256) {
        if (!walletHasActiveMining[user]) return 0;
        return _pendingRewards(tokenMiners[walletActiveTokenId[user]]);
    }

    function getMiningStatus(address user)
        external
        view
        returns (
            bool    active,
            bool    completed,
            uint256 tokenId,
            uint256 startTime,
            uint256 claimedAmount,
            uint256 pendingAmount,
            uint256 totalAccrued,
            uint256 rewardAmount,
            uint256 rewardDuration
        )
    {
        rewardAmount   = REWARD_AMOUNT;
        rewardDuration = REWARD_DURATION;

        tokenId = walletActiveTokenId[user];
        if (tokenId == 0 && !walletHasActiveMining[user]) {
            return (false, false, 0, 0, 0, 0, 0, REWARD_AMOUNT, REWARD_DURATION);
        }

        TokenMinerInfo storage info = tokenMiners[tokenId];
        active        = info.active;
        completed     = info.completed;
        startTime     = info.startTime;
        claimedAmount = info.claimedAmount;
        pendingAmount = _pendingRewards(info);

        if (info.active && info.startTime > 0) {
            uint256 elapsed = block.timestamp - info.startTime;
            totalAccrued = elapsed >= REWARD_DURATION
                ? REWARD_AMOUNT
                : REWARD_AMOUNT * elapsed / REWARD_DURATION;
        } else {
            totalAccrued = info.claimedAmount;
        }
    }

    
    function getTokenMinerInfo(uint256 tokenId)
        external
        view
        returns (
            bool    active,
            bool    completed,
            address miner,
            uint256 startTime,
            uint256 claimedAmount,
            uint256 pendingAmount
        )
    {
        TokenMinerInfo storage info = tokenMiners[tokenId];
        active        = info.active;
        completed     = info.completed;
        miner         = info.miner;
        startTime     = info.startTime;
        claimedAmount = info.claimedAmount;
        pendingAmount = _pendingRewards(info);
    }

  
    function contractBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // ─── Owner utilities ──────────────────────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

   
    function unpause() external onlyOwner {
        _unpause();
    }

  
    function fundContract(uint256 amount) external onlyOwner {
        require(
            rewardToken.transferFrom(msg.sender, address(this), amount),
            "MiningContract: funding transfer failed"
        );
    }

 
    function withdrawRemainingTokens(uint256 amount) external onlyOwner {
        require(
            rewardToken.transfer(owner(), amount),
            "MiningContract: withdrawal failed"
        );
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    function _pendingRewards(TokenMinerInfo storage info)
        internal
        view
        returns (uint256)
    {
        if (!info.active || info.startTime == 0) return 0;

        uint256 elapsed = block.timestamp - info.startTime;
        uint256 accrued;

        if (elapsed >= REWARD_DURATION) {
            accrued = REWARD_AMOUNT;
        } else {
            accrued = REWARD_AMOUNT * elapsed / REWARD_DURATION;
        }

        if (accrued <= info.claimedAmount) return 0;
        return accrued - info.claimedAmount;
    }
}
