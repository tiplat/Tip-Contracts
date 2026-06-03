// =========================================
/*
████████╗██╗██████╗
╚══██╔══╝██║██╔══██╗
   ██║   ██║██████╔╝     T I P
   ██║   ██║██╔═══╝      Agent Registry
   ██║   ██║██║          https://tip.lat
   ╚═╝   ╚═╝╚═╝
*/
// =========================================

/**
 * @title TIPAgentRegistry
 * @notice On-chain registry for AI agents linked to TIP API keys.
 * @dev Each agent is owned by a wallet and linked to an API key hash.
 *      Plaintext API keys are never stored — only keccak256 hashes.
 *      The TIPApiKeys contract remains the authoritative source of truth for key validity.
 *
 *      Architecture:
 *        - agentId-based storage: append-only, no migration needed for new fields.
 *        - ownerAgents mapping: O(1) owner enumeration.
 *        - activeAgentIds array + activeIndex map: O(1) removal via swap-and-pop.
 *        - Event-based indexing for off-chain discovery (preferred for large registries).
 *
 *      Category index mapping (uint8):
 *        0 = ai-agent | 1 = trading-bot | 2 = automation | 3 = data-indexer
 *        4 = social-bot | 5 = analytics | 6 = integration | 7 = other
 *
 *      Designed for future extensions:
 *        - New fields (tags, version, permissions, chainId) can be appended to Agent struct.
 *        - agentId-based lookup means no storage layout breaks on upgrade.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract TIPAgentRegistry {

    // ── Agent ID Counter ──────────────────────────────────────────────────────

    uint256 public agentCount;


    // ── Storage ───────────────────────────────────────────────────────────────

    struct Agent {
        uint256 agentId;        // auto-incremented unique identifier
        address owner;          // wallet that registered the agent
        bytes32 apiKeyHash;     // keccak256 of the associated API key — NEVER the key itself
        string  name;           // human-readable display name
        string  description;    // what the agent does
        string  website;        // optional docs / homepage URL
        string  avatar;         // optional avatar image URL
        uint8   category;       // category index (see mapping above)
        uint256 createdAt;      // block.timestamp at registration
        bool    active;         // false once deactivated
        // NOTE: future fields can be appended here without breaking V1 records.
        //       agentId-keyed storage is append-only — no storage collision risk.
    }

    /// @dev Primary store — agentId → Agent
    mapping(uint256 => Agent) public agents;

    /// @dev Owner enumeration — owner → list of agentIds (includes inactive)
    mapping(address => uint256[]) private ownerAgents;

    /// @dev Active agent list for discovery
    uint256[] private activeAgentIds;

    /// @dev O(1) position tracking for swap-and-pop removal (1-indexed; 0 = not active)
    mapping(uint256 => uint256) private activeIndex;


    // ── Custom Errors ─────────────────────────────────────────────────────────

    error TIPAgentRegistry__AgentNotFound();
    error TIPAgentRegistry__NotAgentOwner();
    error TIPAgentRegistry__AgentAlreadyInactive();
    error TIPAgentRegistry__AgentAlreadyActive();
    error TIPAgentRegistry__EmptyName();
    error TIPAgentRegistry__ZeroKeyHash();


    // ── Events ────────────────────────────────────────────────────────────────

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        bytes32 indexed apiKeyHash,
        string  name,
        uint8   category,
        uint256 createdAt
    );

    event AgentUpdated(
        uint256 indexed agentId,
        address indexed owner,
        string  name,
        uint8   category
    );

    event AgentDeactivated(
        uint256 indexed agentId,
        address indexed owner,
        uint256 deactivatedAt
    );

    event AgentReactivated(
        uint256 indexed agentId,
        address indexed owner,
        uint256 reactivatedAt
    );


    // ── Core Functions ────────────────────────────────────────────────────────

    /**
     * @notice Register a new agent on-chain.
     * @param apiKeyHash   keccak256 of the associated API key (never the key itself).
     * @param name         Human-readable display name.
     * @param description  What the agent does.
     * @param website      Optional docs / homepage URL.
     * @param avatar       Optional avatar image URL.
     * @param category     Category index (0–7).
     * @return agentId     The unique ID assigned to the agent.
     */
    function registerAgent(
        bytes32        apiKeyHash,
        string calldata name,
        string calldata description,
        string calldata website,
        string calldata avatar,
        uint8          category
    ) external returns (uint256 agentId) {
        if (apiKeyHash == bytes32(0))  revert TIPAgentRegistry__ZeroKeyHash();
        if (bytes(name).length == 0)   revert TIPAgentRegistry__EmptyName();

        agentCount++;
        agentId = agentCount;

        agents[agentId] = Agent({
            agentId:     agentId,
            owner:       msg.sender,
            apiKeyHash:  apiKeyHash,
            name:        name,
            description: description,
            website:     website,
            avatar:      avatar,
            category:    category,
            createdAt:   block.timestamp,
            active:      true
        });

        ownerAgents[msg.sender].push(agentId);
        _addToActive(agentId);

        emit AgentRegistered(agentId, msg.sender, apiKeyHash, name, category, block.timestamp);
    }

    /**
     * @notice Update mutable metadata fields of an existing agent.
     * @param agentId      The agent to update. Must be owned by msg.sender.
     * @param name         New display name.
     * @param description  New description.
     * @param website      New website URL.
     * @param avatar       New avatar URL.
     * @param category     New category index.
     */
    function updateAgent(
        uint256        agentId,
        string calldata name,
        string calldata description,
        string calldata website,
        string calldata avatar,
        uint8          category
    ) external {
        Agent storage agent = agents[agentId];
        if (agent.owner == address(0))  revert TIPAgentRegistry__AgentNotFound();
        if (agent.owner != msg.sender)  revert TIPAgentRegistry__NotAgentOwner();
        if (bytes(name).length == 0)    revert TIPAgentRegistry__EmptyName();

        agent.name        = name;
        agent.description = description;
        agent.website     = website;
        agent.avatar      = avatar;
        agent.category    = category;

        emit AgentUpdated(agentId, msg.sender, name, category);
    }

    /**
     * @notice Deactivate an agent. The record is preserved for audit.
     * @param agentId  The agent to deactivate. Must be owned by msg.sender.
     */
    function deactivateAgent(uint256 agentId) external {
        Agent storage agent = agents[agentId];
        if (agent.owner == address(0))  revert TIPAgentRegistry__AgentNotFound();
        if (agent.owner != msg.sender)  revert TIPAgentRegistry__NotAgentOwner();
        if (!agent.active)              revert TIPAgentRegistry__AgentAlreadyInactive();

        agent.active = false;
        _removeFromActive(agentId);

        emit AgentDeactivated(agentId, msg.sender, block.timestamp);
    }

    /**
     * @notice Reactivate a previously deactivated agent.
     * @param agentId  The agent to reactivate. Must be owned by msg.sender.
     */
    function reactivateAgent(uint256 agentId) external {
        Agent storage agent = agents[agentId];
        if (agent.owner == address(0))  revert TIPAgentRegistry__AgentNotFound();
        if (agent.owner != msg.sender)  revert TIPAgentRegistry__NotAgentOwner();
        if (agent.active)               revert TIPAgentRegistry__AgentAlreadyActive();

        agent.active = true;
        _addToActive(agentId);

        emit AgentReactivated(agentId, msg.sender, block.timestamp);
    }


    // ── View Functions ────────────────────────────────────────────────────────

    /**
     * @notice Return full metadata for an agent.
     * @param agentId  Agent ID to query.
     */
    function getAgent(uint256 agentId)
        external
        view
        returns (Agent memory)
    {
        return agents[agentId];
    }

    /**
     * @notice Return all agent IDs owned by an address (active and inactive).
     * @param owner  Wallet address to query.
     */
    function getAgentsByOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        return ownerAgents[owner];
    }

    /**
     * @notice Return IDs of all currently active agents.
     * @dev For registries with thousands of agents, prefer off-chain event indexing.
     *      On-chain use: iterate activeAgentIds, then call getAgent() per ID.
     */
    function getAllActiveAgents()
        external
        view
        returns (uint256[] memory)
    {
        return activeAgentIds;
    }


    // ── Internal Helpers ──────────────────────────────────────────────────────

    function _addToActive(uint256 agentId) internal {
        activeAgentIds.push(agentId);
        activeIndex[agentId] = activeAgentIds.length; // 1-indexed
    }

    function _removeFromActive(uint256 agentId) internal {
        uint256 pos = activeIndex[agentId];
        if (pos == 0) return;

        uint256 lastId = activeAgentIds[activeAgentIds.length - 1];
        activeAgentIds[pos - 1] = lastId;
        activeIndex[lastId] = pos;

        activeAgentIds.pop();
        activeIndex[agentId] = 0;
    }
}
