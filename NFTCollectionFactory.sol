// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./NFTCollection.sol";

contract NFTCollectionFactory is ReentrancyGuard {
    uint256 private _collectionIds;
    
    struct CollectionInfo {
        uint256 id;
        address contractAddress;
        address creator;
        string name;
        string symbol;
        string description;
        uint256 maxSupply;
        uint256 mintPrice;
        string imageUrl;
        uint256 imageCount;
        uint256 createdAt;
        bool isActive;
    }
    
    mapping(uint256 => CollectionInfo) public collections;
    mapping(address => uint256[]) public creatorCollections;
    mapping(address => bool) public isCollection;
    
    uint256 public creationFee = 0.000125 ether;
    address public feeRecipient;
    
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed contractAddress,
        address indexed creator,
        string name,
        string symbol,
        string description,
        uint256 maxSupply,
        uint256 mintPrice,
        uint256 imageCount
    );
    
    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }
    
    function createCollection(
        string memory _name,
        string memory _symbol,
        string memory _description,
        string memory _collectionImage,
        string[] memory _nftImages,
        uint256 _maxSupply,
        uint256 _mintPrice
    ) external payable nonReentrant returns (address) {
        require(bytes(_name).length > 0, "Name required");
        require(bytes(_symbol).length > 0, "Symbol required");
        require(_nftImages.length > 0, "Images required");
        require(_nftImages.length <= 8, "Max 8 images");
        require(_maxSupply > 0 && _maxSupply <= 10000, "Invalid supply");
        require(msg.value >= creationFee, "Insufficient fee");
        
        NFTCollection newCollection = new NFTCollection(
            _name,
            _symbol,
            _description,
            _collectionImage,
            _nftImages,
            _maxSupply,
            _mintPrice,
            msg.sender
        );
        
        _collectionIds++;
        
        collections[_collectionIds] = CollectionInfo({
            id: _collectionIds,
            contractAddress: address(newCollection),
            creator: msg.sender,
            name: _name,
            symbol: _symbol,
            description: _description,
            maxSupply: _maxSupply,
            mintPrice: _mintPrice,
            imageUrl: _collectionImage,
            imageCount: _nftImages.length,
            createdAt: block.timestamp,
            isActive: true
        });
        
        creatorCollections[msg.sender].push(_collectionIds);
        isCollection[address(newCollection)] = true;
        
        if (msg.value > 0) {
            (bool success, ) = payable(feeRecipient).call{value: msg.value}("");
require(success, "Transfer failed");
        }
        
        emit CollectionCreated(
            _collectionIds,
            address(newCollection),
            msg.sender,
            _name,
            _symbol,
            _description,
            _maxSupply,
            _mintPrice,
            _nftImages.length
        );
        
        return address(newCollection);
    }
    
    function getCollection(uint256 _collectionId) external view returns (CollectionInfo memory) {
        require(_collectionId <= _collectionIds, "Collection not found");
        return collections[_collectionId];
    }
    
    function getCreatorCollections(address _creator) external view returns (uint256[] memory) {
        return creatorCollections[_creator];
    }
    
    function getActiveCollections() external view returns (CollectionInfo[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= _collectionIds; i++) {
            if (collections[i].isActive) {
                activeCount++;
            }
        }
        
        CollectionInfo[] memory activeCollections = new CollectionInfo[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= _collectionIds; i++) {
            if (collections[i].isActive) {
                activeCollections[index++] = collections[i];
            }
        }
        
        return activeCollections;
    }
    
    function getAllCollections() external view returns (CollectionInfo[] memory) {
        CollectionInfo[] memory allCollections = new CollectionInfo[](_collectionIds);
        
        for (uint256 i = 1; i <= _collectionIds; i++) {
            allCollections[i - 1] = collections[i];
        }
        
        return allCollections;
    }
    
    function totalCollections() external view returns (uint256) {
        return _collectionIds;
    }
    
    function deactivateCollection(uint256 _collectionId) external {
        require(_collectionId <= _collectionIds, "Collection not found");
        require(collections[_collectionId].creator == msg.sender, "Not creator");
        collections[_collectionId].isActive = false;
    }
    
    function updateCreationFee(uint256 _newFee) external {
        require(msg.sender == feeRecipient, "Not authorized");
        creationFee = _newFee;
    }
    
    function updateFeeRecipient(address _newRecipient) external {
        require(msg.sender == feeRecipient, "Not authorized");
        feeRecipient = _newRecipient;
    }
}
