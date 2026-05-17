// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFTCollection is ERC721, Ownable, ReentrancyGuard {
    uint256 private _tokenIds;
    uint256 public maxSupply;
    uint256 public mintPrice;
    string public description;
    string public collectionImage;
    address public creator;
    bool public mintingActive = true;
    
    string[] public nftImages;
    
    mapping(uint256 => uint256) public tokenImageIndex;
    mapping(address => uint256) public mintedByAddress;
    uint256 public maxMintPerAddress = 10;
    
    string private _contractURI;
    
    event TokenMinted(address indexed to, uint256 indexed tokenId, uint256 imageIndex);
    
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _description,
        string memory _collectionImage,
        string[] memory _nftImages,
        uint256 _maxSupply,
        uint256 _mintPrice,
        address _creator
    ) ERC721(_name, _symbol) Ownable(_creator) {
        description = _description;
        collectionImage = _collectionImage;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        creator = _creator;
        
        for (uint256 i = 0; i < _nftImages.length; i++) {
            nftImages.push(_nftImages[i]);
        }
        
        require(nftImages.length > 0, "At least one NFT image required");
        _contractURI = _collectionImage;
    }
    
    function mint(address to) external payable nonReentrant {
        require(mintingActive, "Minting paused");
        require(_tokenIds < maxSupply, "Max supply reached");
        require(msg.value >= mintPrice, "Insufficient payment");
        require(mintedByAddress[to] < maxMintPerAddress, "Max mint reached");
        
        _tokenIds++;
        uint256 tokenId = _tokenIds;
        
        _safeMint(to, tokenId);
        
        uint256 imageIndex = _getRandomImageIndex(tokenId);
        tokenImageIndex[tokenId] = imageIndex;
        
        mintedByAddress[to]++;
        
        if (msg.value > 0) {
            (bool success, ) = creator.call{value: msg.value}("");
require(success, "Transfer failed");
        }
        
        emit TokenMinted(to, tokenId, imageIndex);
    }
    
    function batchMint(address to, uint256 quantity) external payable nonReentrant {
        require(mintingActive, "Minting paused");
        require(quantity > 0 && quantity <= 10, "Invalid quantity");
        require(_tokenIds + quantity <= maxSupply, "Exceeds max supply");
        require(msg.value >= mintPrice * quantity, "Insufficient payment");
        require(mintedByAddress[to] + quantity <= maxMintPerAddress, "Exceeds max mint");
        
        for (uint256 i = 0; i < quantity; i++) {
            _tokenIds++;
            uint256 tokenId = _tokenIds;
            
            _safeMint(to, tokenId);
            
            uint256 imageIndex = _getRandomImageIndex(tokenId);
            tokenImageIndex[tokenId] = imageIndex;
            
            emit TokenMinted(to, tokenId, imageIndex);
        }
        
        mintedByAddress[to] += quantity;
        
        if (msg.value > 0) {
            (bool success, ) = creator.call{value: msg.value}("");
require(success, "Transfer failed");
        }
    }
    
    function _getRandomImageIndex(uint256 tokenId) private view returns (uint256) {
        uint256 randomHash = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            tokenId
        )));
        
        return randomHash % nftImages.length;
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_ownerOf(tokenId) != address(0), "Nonexistent token");

    uint256 imageIndex = tokenImageIndex[tokenId];
    string memory image = nftImages[imageIndex];

    return string(abi.encodePacked(
        '{"name":"NFT #',
        Strings.toString(tokenId),
        '","description":"',
        description,
        '","image":"',
        image,
        '"}'
    ));
}
    
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }
    
    function setContractURI(string memory newContractURI) external onlyOwner {
        _contractURI = newContractURI;
    }
    
    function toggleMinting() external onlyOwner {
        mintingActive = !mintingActive;
    }
    
    function updatePrice(uint256 _newPrice) external onlyOwner {
        mintPrice = _newPrice;
    }
    
    function updateMaxMintPerAddress(uint256 _maxMint) external onlyOwner {
        maxMintPerAddress = _maxMint;
    }
    
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");
        (bool success, ) = owner().call{value: balance}("");
require(success, "Transfer failed");
    }
    
    function totalSupply() public view returns (uint256) {
        return _tokenIds;
    }
    
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= _tokenIds && index < tokenCount; i++) {
            if (_ownerOf(i) == owner) {
                tokenIds[index++] = i;
            }
        }
        
        return tokenIds;
    }
    
    function getCollectionInfo() external view returns (
        string memory name_,
        string memory symbol_,
        string memory description_,
        string memory image_,
        uint256 totalSupply_,
        uint256 maxSupply_,
        uint256 mintPrice_,
        address creator_,
        bool mintingActive_
    ) {
        return (
            name(),
            symbol(),
            description,
            collectionImage,
            totalSupply(),
            maxSupply,
            mintPrice,
            creator,
            mintingActive
        );
    }
    
    function getImageCount() public view returns (uint256) {
        return nftImages.length;
    }
    
    function getImageByIndex(uint256 index) public view returns (string memory) {
        require(index < nftImages.length, "Index out of bounds");
        return nftImages[index];
    }
    
    function getAllImages() public view returns (string[] memory) {
        return nftImages;
    }
    
    function getTokenImage(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        uint256 imageIndex = tokenImageIndex[tokenId];
        require(imageIndex < nftImages.length, "Invalid image index");
        return nftImages[imageIndex];
    }
}
