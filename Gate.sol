// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract Gate {
    struct GateRule {
        address creator;
        address nftContract;
        bool nftRequired;
        address tokenContract;
        uint256 minTokenBalance;
        bool tokenRequired;
        uint256 minEthBalance;
        bool ethRequired;
        bool exists;
    }

    uint256 public constant CREATION_FEE = 0.0005 ether;

    address public immutable platformWallet;

    mapping(bytes32 => GateRule) private rules;

    event GateCreated(bytes32 indexed pageId, address indexed creator);
    event GateUpdated(bytes32 indexed pageId, address indexed creator);
    event GateDeleted(bytes32 indexed pageId);

    constructor(address _platformWallet) {
        require(_platformWallet != address(0), "Platform wallet cannot be zero");
        platformWallet = _platformWallet;
    }

    modifier onlyCreator(bytes32 pageId) {
        require(rules[pageId].exists, "Gate does not exist");
        require(rules[pageId].creator == msg.sender, "Not the gate creator");
        _;
    }

    function createGate(
        string calldata pageIdStr,
        address nftContract,
        bool nftRequired,
        address tokenContract,
        uint256 minTokenBalance,
        bool tokenRequired,
        uint256 minEthBalance,
        bool ethRequired
    ) external payable {
        require(msg.value >= CREATION_FEE, "Insufficient creation fee (0.0005 ETH required)");

        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));
        require(!rules[pageId].exists, "Gate already exists");

        rules[pageId] = GateRule({
            creator: msg.sender,
            nftContract: nftContract,
            nftRequired: nftRequired,
            tokenContract: tokenContract,
            minTokenBalance: minTokenBalance,
            tokenRequired: tokenRequired,
            minEthBalance: minEthBalance,
            ethRequired: ethRequired,
            exists: true
        });

        (bool sent, ) = payable(platformWallet).call{value: CREATION_FEE}("");
        require(sent, "Fee transfer failed");

        uint256 excess = msg.value - CREATION_FEE;
        if (excess > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: excess}("");
            require(refunded, "Refund failed");
        }

        emit GateCreated(pageId, msg.sender);
    }

    function updateGate(
        string calldata pageIdStr,
        address nftContract,
        bool nftRequired,
        address tokenContract,
        uint256 minTokenBalance,
        bool tokenRequired,
        uint256 minEthBalance,
        bool ethRequired
    ) external onlyCreator(keccak256(abi.encodePacked(pageIdStr))) {
        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));

        GateRule storage rule = rules[pageId];
        rule.nftContract = nftContract;
        rule.nftRequired = nftRequired;
        rule.tokenContract = tokenContract;
        rule.minTokenBalance = minTokenBalance;
        rule.tokenRequired = tokenRequired;
        rule.minEthBalance = minEthBalance;
        rule.ethRequired = ethRequired;

        emit GateUpdated(pageId, msg.sender);
    }

  
    function deleteGate(string calldata pageIdStr)
        external
        onlyCreator(keccak256(abi.encodePacked(pageIdStr)))
    {
        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));
        delete rules[pageId];
        emit GateDeleted(pageId);
    }

  
    function getGate(string calldata pageIdStr)
        external
        view
        returns (GateRule memory)
    {
        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));
        require(rules[pageId].exists, "Gate does not exist");
        return rules[pageId];
    }

   
    function gateExists(string calldata pageIdStr) external view returns (bool) {
        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));
        return rules[pageId].exists;
    }

   
    function checkAccess(string calldata pageIdStr, address wallet)
        external
        view
        returns (bool hasAccess, string memory failReason)
    {
        bytes32 pageId = keccak256(abi.encodePacked(pageIdStr));
        if (!rules[pageId].exists) {
            return (false, "Gate does not exist");
        }

        GateRule storage rule = rules[pageId];

        if (rule.nftRequired && rule.nftContract != address(0)) {
            IERC721 nft = IERC721(rule.nftContract);
            if (nft.balanceOf(wallet) == 0) {
                return (false, "Missing required NFT");
            }
        }

        if (rule.tokenRequired && rule.tokenContract != address(0)) {
            IERC20 token = IERC20(rule.tokenContract);
            if (token.balanceOf(wallet) < rule.minTokenBalance) {
                return (false, "Insufficient token balance");
            }
        }

        if (rule.ethRequired) {
            if (wallet.balance < rule.minEthBalance) {
                return (false, "Insufficient ETH balance");
            }
        }

        return (true, "");
    }
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}
