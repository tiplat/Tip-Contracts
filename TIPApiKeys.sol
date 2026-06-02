// =========================================
/*
████████╗██╗██████╗
╚══██╔══╝██║██╔══██╗
   ██║   ██║██████╔╝     T I P
   ██║   ██║██╔═══╝      Developer API Key Registry
   ██║   ██║██║          https://tip.lat
   ╚═╝   ╚═╝╚═╝
*/
// =========================================

/**
 * @title TIPApiKeys
 * @notice Decentralized API key registry for the TIP Developer Platform.
 * @dev Stores key hashes only — plaintext keys never touch the chain.
 *      Designed as a permanent foundation for:
 *        - External AI Agents
 *        - Developer Integrations
 *        - Manifest Authentication
 *        - MCP Clients
 *        - Agent-to-Agent Communication
 *        - Automation Bots
 *        - Third-Party Applications
 *        - Future Commercial API Access
 *
 *      Architecture is intentionally future-proof:
 *        - permissionsBitmap reserved for Manifest scoped auth (V1+)
 *        - struct layout leaves room for expiry, rotation, rate-limit tiers
 *        - O(1) isValidKey() for hot-path middleware validation
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract TIPApiKeys {

    // ── Storage ───────────────────────────────────────────────────────────────

    struct ApiKey {
        bytes32  keyHash;           // keccak256 of the raw API key — NEVER the key itself
        address  owner;             // wallet that created the key
        string   name;              // human-readable label (e.g. "Claude Agent")
        uint256  createdAt;         // block.timestamp at creation
        bool     active;            // false once revoked
        uint256  permissionsBitmap; // scoped access flags (see PermissionBits below)
        // NOTE: future fields (expiresAt, usageCount, rateLimit, tier, delegateTo)
        //       can be added in a successor contract without breaking V1 hashes.
    }

    /// @dev Primary key store — hash → metadata
    mapping(bytes32 => ApiKey) public keys;

    /// @dev Enumerate keys by owner
    mapping(address => bytes32[]) private ownerKeys;

    /// @dev O(1) deduplication guard per owner
    mapping(address => mapping(bytes32 => bool)) private ownerHasKey;


    // ── Permission Bits ───────────────────────────────────────────────────────
    //
    //  Bit  | Value | Scope
    //  -----|-------|---------------------------
    //   0   |   1   | Forms
    //   1   |   2   | Streams
    //   2   |   4   | Collections
    //   3   |   8   | Marketplace
    //   4   |  16   | Tokens
    //   5   |  32   | Social
    //   6   |  64   | Identity
    //   7   | 128   | Read Only
    //   8   | 256   | Write Access
    //   9+  |  --   | Reserved for future scopes
    //
    //  These bits are stored now so Manifest Authentication can enforce them
    //  without a contract migration.


    // ── Custom Errors ─────────────────────────────────────────────────────────

    error TIPApiKeys__KeyAlreadyExists();
    error TIPApiKeys__KeyNotFound();
    error TIPApiKeys__NotKeyOwner();
    error TIPApiKeys__KeyAlreadyRevoked();
    error TIPApiKeys__EmptyName();
    error TIPApiKeys__ZeroHash();


    // ── Events ────────────────────────────────────────────────────────────────

    event ApiKeyCreated(
        bytes32 indexed keyHash,
        address indexed owner,
        string  name,
        uint256 permissionsBitmap,
        uint256 createdAt
    );

    event ApiKeyRevoked(
        bytes32 indexed keyHash,
        address indexed owner,
        uint256 revokedAt
    );


    // ── Core Functions ────────────────────────────────────────────────────────

    /**
     * @notice Register a new API key hash on-chain.
     * @param  keyHash          keccak256 of the plaintext API key (computed client-side).
     * @param  name             Human-readable label for the key.
     * @param  permissionsBitmap Bitmask of scoped permissions (see PermissionBits).
     *
     * @dev The caller is the owner. Duplicate hashes are rejected globally.
     *      ownerHasKey prevents a single wallet registering the same hash twice.
     */
    function createKey(
        bytes32        keyHash,
        string calldata name,
        uint256        permissionsBitmap
    ) external {
        if (keyHash == bytes32(0))        revert TIPApiKeys__ZeroHash();
        if (bytes(name).length == 0)      revert TIPApiKeys__EmptyName();
        if (keys[keyHash].owner != address(0)) revert TIPApiKeys__KeyAlreadyExists();
        if (ownerHasKey[msg.sender][keyHash])  revert TIPApiKeys__KeyAlreadyExists();

        keys[keyHash] = ApiKey({
            keyHash:           keyHash,
            owner:             msg.sender,
            name:              name,
            createdAt:         block.timestamp,
            active:            true,
            permissionsBitmap: permissionsBitmap
        });

        ownerKeys[msg.sender].push(keyHash);
        ownerHasKey[msg.sender][keyHash] = true;

        emit ApiKeyCreated(keyHash, msg.sender, name, permissionsBitmap, block.timestamp);
    }

    /**
     * @notice Revoke an existing API key.
     * @param  keyHash  Hash of the key to revoke. Must be owned by msg.sender.
     *
     * @dev Sets active = false. The hash record remains for audit purposes.
     *      isValidKey() will return false after revocation.
     */
    function revokeKey(bytes32 keyHash) external {
        ApiKey storage key = keys[keyHash];

        if (key.owner == address(0))  revert TIPApiKeys__KeyNotFound();
        if (key.owner != msg.sender)  revert TIPApiKeys__NotKeyOwner();
        if (!key.active)              revert TIPApiKeys__KeyAlreadyRevoked();

        key.active = false;

        emit ApiKeyRevoked(keyHash, msg.sender, block.timestamp);
    }


    // ── View Functions ────────────────────────────────────────────────────────

    /**
     * @notice O(1) validation check — hot path for Manifest Authentication middleware.
     * @param  keyHash  Hash of the API key to validate.
     * @return true if the key exists and has not been revoked.
     */
    function isValidKey(bytes32 keyHash) external view returns (bool) {
        ApiKey storage key = keys[keyHash];
        return key.owner != address(0) && key.active;
    }

    /**
     * @notice Return all key hashes registered by an owner address.
     * @param  owner  Wallet address to query.
     * @return Array of keyHash values (includes revoked keys for full history).
     */
    function getOwnerKeys(address owner) external view returns (bytes32[] memory) {
        return ownerKeys[owner];
    }

    /**
     * @notice Return full metadata for a key.
     * @param  keyHash  Hash to query.
     * @return Populated ApiKey struct (zero-value if not found).
     */
    function getKeyMetadata(bytes32 keyHash)
        external
        view
        returns (ApiKey memory)
    {
        return keys[keyHash];
    }
}
