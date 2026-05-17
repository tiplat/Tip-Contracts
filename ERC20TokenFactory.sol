// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CustomERC20Token is ERC20, Ownable {
    string public tokenImageUrl;

    string public tokenDescription;

    address public creator;

    uint256 public salePrice;

    bool public saleActive = true;

    uint256 public maxPurchasePerTx = 1_000_000_000 * 10 ** 18;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event SalePriceUpdated(uint256 newPrice);
    event SaleToggled(bool active);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        string memory _imageUrl,
        string memory _description,
        uint256 _salePrice,
        address _creator
    ) ERC20(_name, _symbol) Ownable(_creator) {
        creator = _creator;
        tokenImageUrl = _imageUrl;
        tokenDescription = _description;
        salePrice = _salePrice;

        _mint(_creator, _totalSupply * 10 ** decimals());
    }

    function buyTokens(uint256 _amount) external payable {
        require(saleActive, "Sale not active");
        require(_amount > 0, "Amount must be > 0");
        require(_amount <= maxPurchasePerTx, "Exceeds max purchase");

        uint256 cost = (_amount * salePrice) / 10 ** decimals();
        require(msg.value >= cost, "Insufficient payment");
        require(balanceOf(creator) >= _amount, "Insufficient tokens available");

        _transfer(creator, msg.sender, _amount);

        if (msg.value > 0) {
            (bool success, ) = creator.call{value: msg.value}("");
            require(success, "Transfer failed");
        }

        emit TokensPurchased(msg.sender, _amount, cost);
    }

    function updateSalePrice(uint256 _newPrice) external onlyOwner {
        salePrice = _newPrice;
        emit SalePriceUpdated(_newPrice);
    }

    function toggleSale() external onlyOwner {
        saleActive = !saleActive;
        emit SaleToggled(saleActive);
    }

    function updateMaxPurchase(uint256 _maxPurchase) external onlyOwner {
        maxPurchasePerTx = _maxPurchase;
    }

    function getTokenInfo()
        external
        view
        returns (
            string memory name_,
            string memory symbol_,
            uint256 totalSupply_,
            uint256 decimals_,
            string memory imageUrl_,
            string memory description_,
            uint256 salePrice_,
            bool saleActive_,
            address creator_,
            uint256 creatorBalance_
        )
    {
        return (
            name(),
            symbol(),
            totalSupply(),
            decimals(),
            tokenImageUrl,
            tokenDescription,
            salePrice,
            saleActive,
            creator,
            balanceOf(creator)
        );
    }

    function calculateCost(uint256 _amount) external view returns (uint256) {
        return (_amount * salePrice) / 10 ** decimals();
    }
}

contract ERC20TokenFactory is ReentrancyGuard {

    uint256 private _tokenIds;

    struct TokenInfo {
        uint256 id;
        address contractAddress;
        address creator;
        string name;
        string symbol;
        uint256 totalSupply;  
        string imageUrl;
        string description;
        uint256 salePrice;     
        uint256 createdAt;
        bool isActive;
    }

    mapping(uint256 => TokenInfo) public tokens;

    mapping(address => uint256[]) public creatorTokens;

    mapping(address => bool) public isToken;

    uint256 public creationFee =  0.00005 ether;

    address public feeRecipient;

    event TokenCreated(
        uint256 indexed tokenId,
        address indexed contractAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 salePrice
    );

    event TokenDeactivated(uint256 indexed tokenId);

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    function createToken(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        string memory _imageUrl,
        string memory _description,
        uint256 _salePrice
    ) external payable nonReentrant {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_symbol).length > 0, "Symbol cannot be empty");
        require(_totalSupply > 0 && _totalSupply <= 1_000_000_000, "Invalid total supply");
        require(_salePrice > 0, "Sale price must be > 0");
        require(msg.value >= creationFee, "Insufficient creation fee");

        CustomERC20Token newToken = new CustomERC20Token(
            _name,
            _symbol,
            _totalSupply,
            _imageUrl,
            _description,
            _salePrice,
            msg.sender
        );

        _tokenIds++;

        tokens[_tokenIds] = TokenInfo({
            id: _tokenIds,
            contractAddress: address(newToken),
            creator: msg.sender,
            name: _name,
            symbol: _symbol,
            totalSupply: _totalSupply,
            imageUrl: _imageUrl,
            description: _description,
            salePrice: _salePrice,
            createdAt: block.timestamp,
            isActive: true
        });

        creatorTokens[msg.sender].push(_tokenIds);
        isToken[address(newToken)] = true;

        if (msg.value > 0) {
            (bool success, ) = feeRecipient.call{value: msg.value}("");
            require(success, "Transfer failed");
        }

        emit TokenCreated(
            _tokenIds,
            address(newToken),
            msg.sender,
            _name,
            _symbol,
            _totalSupply,
            _salePrice
        );
    }

    function deactivateToken(uint256 _tokenId) external {
        require(_tokenId <= _tokenIds, "Token does not exist");
        require(tokens[_tokenId].creator == msg.sender, "Not the creator");
        tokens[_tokenId].isActive = false;
        emit TokenDeactivated(_tokenId);
    }

    function updateCreationFee(uint256 _newFee) external {
        require(msg.sender == feeRecipient, "Only fee recipient can update fee");
        creationFee = _newFee;
    }

    function updateFeeRecipient(address _newRecipient) external {
        require(msg.sender == feeRecipient, "Only current fee recipient can update");
        feeRecipient = _newRecipient;
    }

    function getToken(uint256 _tokenId) external view returns (TokenInfo memory) {
        require(_tokenId <= _tokenIds, "Token does not exist");
        return tokens[_tokenId];
    }

    function getCreatorTokens(address _creator) external view returns (uint256[] memory) {
        return creatorTokens[_creator];
    }

    function getAllTokens() external view returns (TokenInfo[] memory) {
        TokenInfo[] memory allTokens = new TokenInfo[](_tokenIds);
        for (uint256 i = 1; i <= _tokenIds; i++) {
            allTokens[i - 1] = tokens[i];
        }
        return allTokens;
    }

    function getActiveTokens() external view returns (TokenInfo[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= _tokenIds; i++) {
            if (tokens[i].isActive) activeCount++;
        }

        TokenInfo[] memory activeTokens = new TokenInfo[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= _tokenIds; i++) {
            if (tokens[i].isActive) {
                activeTokens[index] = tokens[i];
                index++;
            }
        }
        return activeTokens;
    }

    function totalTokens() external view returns (uint256) {
        return _tokenIds;
    }
}
