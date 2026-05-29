// =========================================
/*
████████╗██╗██████╗
╚══██╔══╝██║██╔══██╗
   ██║   ██║██████╔╝     T I P
   ██║   ██║██╔═══╝      Decentralized On-Chain identities
   ██║   ██║██║          https://tip.lat
   ╚═╝   ╚═╝╚═╝
*/
// =========================================

/**
 * @title TIPidentity
 * @notice Decentralized on-chain identities protocol by TIP
 * @dev Core contract for TIP ecosystem
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ProfileIdentitySBT
 * @notice Soulbound (non-transferable) ERC-721 identity badge for TIPSocial profiles.
 *
 *         Metadata is generated entirely on-chain:
 *           - Username and profile image are fetched live from the TIPSocial contract.
 *           - tokenURI() returns a base64-encoded JSON data URI.
 *           - contractURI() exposes collection metadata for OpenSea.
 *
 *         Transfer prevention uses the OpenZeppelin v5 `_update` hook so that
 *         the subsequent checkOnERC721Received call in safeTransferFrom remains
 *         reachable at the source level, avoiding compiler unreachable-code warnings.
 */

// ── TIPSocial interface (username + profile image source) ─────────────────────

interface ITIPSocial {
    function users(address wallet)
        external
        view
        returns (
            string memory username,
            string memory avatar,
            string memory banner,
            string memory bio,
            string memory website,
            uint256 postCount,
            uint256 followerCount,
            uint256 followingCount,
            uint256 totalTipsReceived,
            uint256 totalTipsSent,
            bool    exists
        );
}

// ── Contract ──────────────────────────────────────────────────────────────────

contract ProfileIdentitySBT is ERC721, Ownable {
    using Strings for uint256;
    using Strings for address;

    // ── Constants ─────────────────────────────────────────────────────────────

    /// @dev TIPSocial contract on Base mainnet — sole source of usernames and profile images.
    address public constant SOCIAL_CONTRACT =
        0xfe758Dc0232D2778ED685164742887c7f1582Acf;

    // ── State ─────────────────────────────────────────────────────────────────

    uint256 private _nextTokenId;

    mapping(address => uint256) public addressToTokenId;
    mapping(address => string)  public addressToUsernameTip;
    mapping(address => bool)    public hasMinted;

    /// @notice Forward registry — both "alice" and "alice.tip" map to the owner.
    mapping(string => address) public usernameToAddress;

    /// @notice Global uniqueness guard — prevents duplicate .tip identities.
    mapping(string => bool) public usernameTaken;

    // ── Events ────────────────────────────────────────────────────────────────

    event ProfileMinted(
        address indexed user,
        uint256 indexed tokenId,
        string  usernameTip
    );

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor() ERC721("Tip Identity", "TIPSBT") Ownable(msg.sender) {
        _nextTokenId = 1;
    }

    // ── Mint ──────────────────────────────────────────────────────────────────

    /**
     * @notice Mint a soulbound .tip identity NFT for the caller.
     *         Username and profile image are fetched on-chain from TIPSocial.
     *         Only msg.sender can mint their own identity — no arbitrary address input.
     */
    function mintProfile() external {
        address user = msg.sender;

        require(!hasMinted[user], "ProfileIdentitySBT: wallet already has an SBT");

        // Fetch username and existence flag directly from TIPSocial — no frontend input.
        (string memory rawUsername, , , , , , , , , , bool exists) =
            ITIPSocial(SOCIAL_CONTRACT).users(user);

        require(exists,                        "ProfileIdentitySBT: no TIPSocial profile found");
        require(bytes(rawUsername).length > 0, "ProfileIdentitySBT: username cannot be empty");

        // Lowercase the full raw username so "TIP", "Tip", and "tip" all
        // resolve to the same base identity before any suffix logic runs.
        string memory lowerUsername = _toLower(rawUsername);

        // Normalize: strip any existing .tip/.TIP/etc. suffix (case-insensitive)
        // before appending the canonical lowercase ".tip" once.
        string memory baseUsername = _endsWithTip(lowerUsername)
            ? _stripTipSuffix(lowerUsername)
            : lowerUsername;

        string memory usernameTip = string(abi.encodePacked(baseUsername, ".tip"));

        // Enforce global uniqueness of .tip identities.
        require(!usernameTaken[usernameTip], "ProfileIdentitySBT: identity already taken");

        uint256 tokenId = _nextTokenId++;

        hasMinted[user]            = true;
        addressToTokenId[user]     = tokenId;
        addressToUsernameTip[user] = usernameTip;
        usernameTaken[usernameTip] = true;

        // Registry: accept both bare and .tip-suffixed lookups.
        usernameToAddress[baseUsername] = user;
        usernameToAddress[usernameTip]  = user;

        _mint(user, tokenId);

        emit ProfileMinted(user, tokenId, usernameTip);
    }

    // ── On-chain metadata ─────────────────────────────────────────────────────

    /**
     * @notice Returns a base64-encoded JSON data URI for the given token.
     *         The profile image is fetched live from the TIPSocial contract
     *         so it always stays in sync with the user's current avatar.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireOwned(tokenId);
        return _buildTokenURI(ownerOf(tokenId));
    }

    /**
     * @notice Returns base64-encoded collection metadata for OpenSea.
     *         Implements the OpenSea contractURI() standard.
     */
    function contractURI() public pure returns (string memory) {
        bytes memory json = abi.encodePacked(
            '{"name":"Tip Identity",'
            '"description":"Soulbound identity profiles on Base",'
            '"image":"",'
            '"external_link":"https://base.org"}'
        );
        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(json))
        );
    }

    /**
     * @dev Builds the on-chain JSON metadata for a given wallet.
     *      Fetches the avatar from TIPSocial; falls back to empty string on error.
     *      Name is set to exactly "username.tip" — no token ID appended, no duplication.
     */
    function _buildTokenURI(address user)
        internal
        view
        returns (string memory)
    {
        string memory usernameTip = addressToUsernameTip[user];

        // Fetch profile image from TIPSocial contract.
        // Using try/catch so a broken social contract never breaks tokenURI().
        string memory profileImage = "";
        try ITIPSocial(SOCIAL_CONTRACT).users(user) returns (
            string memory,   // username
            string memory avatar,
            string memory,   // banner
            string memory,   // bio
            string memory,   // website
            uint256,         // postCount
            uint256,         // followerCount
            uint256,         // followingCount
            uint256,         // totalTipsReceived
            uint256,         // totalTipsSent
            bool             // exists
        ) {
            profileImage = avatar;
        } catch {}

        bytes memory json = abi.encodePacked(
            '{"name":"',         usernameTip,   '",'
            '"description":"Soulbound Profile Identity",'
            '"image":"',         profileImage,  '",'
            '"attributes":['
                '{"trait_type":"Identity","value":"TIP"},'
                '{"trait_type":"Soulbound","value":"YES"}'
            ']}'
        );

        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(json))
        );
    }

    // ── Registry lookup ───────────────────────────────────────────────────────

    /**
     * @notice Resolve a .tip username to its owner wallet address.
     *         Accepts "alice" or "alice.tip" — both return the same address.
     * @return owner The minting wallet, or address(0) if not registered.
     */
    function resolveUsername(string calldata username)
        external
        view
        returns (address owner)
    {
        return usernameToAddress[username];
    }

    /**
     * @notice Returns full identity info for a wallet in one call.
     */
    function identityOf(address user)
        external
        view
        returns (
            uint256 tokenId,
            string memory usernameTip,
            bool minted
        )
    {
        return (
            addressToTokenId[user],
            addressToUsernameTip[user],
            hasMinted[user]
        );
    }

    // ── Soulbound: block transfers via _update ────────────────────────────────

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) {
            revert("ProfileIdentitySBT: soulbound tokens cannot be transferred or burned");
        }
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert("ProfileIdentitySBT: approvals are disabled for soulbound tokens");
    }

    function setApprovalForAll(address, bool) public pure override {
        revert("ProfileIdentitySBT: approvals are disabled for soulbound tokens");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// @notice Returns the total number of SBTs minted.
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @dev Returns true if `s` ends with ".tip" in any capitalisation
     *      (.tip / .TIP / .Tip / .tIp etc.).
     *      Operates by lowercasing the trailing 4 bytes before comparing,
     *      so it is safe to call on already-lowercased strings too.
     */
    function _endsWithTip(string memory s) internal pure returns (bool) {
        bytes memory sb     = bytes(s);
        bytes memory suffix = bytes(".tip"); // canonical lowercase reference
        if (sb.length < suffix.length) return false;
        uint256 offset = sb.length - suffix.length;
        for (uint256 i = 0; i < suffix.length; i++) {
            bytes1 c = sb[offset + i];
            // Lowercase A-Z (0x41–0x5A) → a-z (0x61–0x7A)
            if (c >= 0x41 && c <= 0x5A) c = bytes1(uint8(c) + 32);
            if (c != suffix[i]) return false;
        }
        return true;
    }

    /**
     * @dev Strips the trailing 4 characters (".tip" in any case) from `s`.
     *      Caller must ensure _endsWithTip(s) is true before calling.
     */
    function _stripTipSuffix(string memory s) internal pure returns (string memory) {
        bytes memory sb     = bytes(s);
        bytes memory result = new bytes(sb.length - 4);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = sb[i];
        }
        return string(result);
    }

    /**
     * @dev Returns a fully lowercase copy of `s`.
     *      Converts every ASCII uppercase letter (A-Z) to its lowercase
     *      equivalent (a-z); all other bytes are passed through unchanged.
     *      Applied to the raw username before any suffix logic so that
     *      "TIP", "Tip", and "tip" all collapse to the same identity.
     */
    function _toLower(string memory s) internal pure returns (string memory) {
        bytes memory sb     = bytes(s);
        bytes memory result = new bytes(sb.length);
        for (uint256 i = 0; i < sb.length; i++) {
            bytes1 c = sb[i];
            if (c >= 0x41 && c <= 0x5A) {
                result[i] = bytes1(uint8(c) + 32);
            } else {
                result[i] = c;
            }
        }
        return string(result);
    }
}
