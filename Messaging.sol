// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface ITIPSocial {
    function users(address) external view returns (
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
        bool exists
    );
}

contract Messaging {
    struct Message {
        uint256 id;
        address sender;
        address recipient;
        string content;
        string imageUrl;
        uint256 tipAmount;
        uint256 timestamp;
        MessageType messageType;
        bool exists;
    }

    enum MessageType {
        TEXT,
        IMAGE,
        TIP
    }

    struct Chat {
        address user1;
        address user2;
        uint256 messageCount;
        uint256 lastMessageTimestamp;
        string lastMessageContent;
        bool exists;
    }

    mapping(bytes32 => Message[]) public chatMessages;
    mapping(address => bytes32[]) public userChats;
    mapping(bytes32 => Chat) public chats;
    mapping(address => mapping(address => bool)) public hasActiveChat;
    
    mapping(address => mapping(bytes32 => bool)) public chatDeleted;
    
    mapping(address => mapping(address => bool)) public isBlocked;
    mapping(address => address[]) public blockedUsers;
    mapping(address => mapping(address => uint256)) public blockedUserIndex;
    
    uint256 public totalMessages;
    ITIPSocial public profileContract;

    event MessageSent(
        address indexed sender,
        address indexed recipient,
        string content,
        string imageUrl,
        uint256 tipAmount,
        MessageType messageType,
        uint256 timestamp
    );
    
    event ChatCreated(
        address indexed user1,
        address indexed user2,
        bytes32 indexed chatId
    );

    event ChatDeleted(
        address indexed user,
        address indexed otherUser,
        bytes32 indexed chatId
    );

    event UserBlocked(
        address indexed blocker,
        address indexed blocked
    );

    event UserUnblocked(
        address indexed blocker,
        address indexed unblocked
    );

    constructor(address _profileContractAddress) {
        profileContract = ITIPSocial(_profileContractAddress);
    }

    modifier userExists(address _user) {
        (, , , , , , , , , , bool exists) = profileContract.users(_user);
        require(exists, "User does not exist");
        _;
    }

    modifier notBlocked(address _recipient) {
        require(!isBlocked[_recipient][msg.sender], "You are blocked by this user");
        _;
    }

    modifier hasNotBlockedRecipient(address _recipient) {
        require(!isBlocked[msg.sender][_recipient], "You have blocked this user");
        _;
    }

    function getChatId(address user1, address user2) public pure returns (bytes32) {
        return user1 < user2 ? 
            keccak256(abi.encodePacked(user1, user2)) : 
            keccak256(abi.encodePacked(user2, user1));
    }

    function blockUser(address _userToBlock) public userExists(msg.sender) userExists(_userToBlock) {
        require(_userToBlock != msg.sender, "Cannot block yourself");
        require(!isBlocked[msg.sender][_userToBlock], "User already blocked");
        
        isBlocked[msg.sender][_userToBlock] = true;
        blockedUserIndex[msg.sender][_userToBlock] = blockedUsers[msg.sender].length;
        blockedUsers[msg.sender].push(_userToBlock);
        
        bytes32 chatId = getChatId(msg.sender, _userToBlock);
        if (chats[chatId].exists) {
            chatDeleted[msg.sender][chatId] = true;
        }
        
        emit UserBlocked(msg.sender, _userToBlock);
    }

    function unblockUser(address _userToUnblock) public {
        require(isBlocked[msg.sender][_userToUnblock], "User is not blocked");
        
        isBlocked[msg.sender][_userToUnblock] = false;
        
        uint256 indexToRemove = blockedUserIndex[msg.sender][_userToUnblock];
        uint256 lastIndex = blockedUsers[msg.sender].length - 1;
        
        if (indexToRemove != lastIndex) {
            address lastUser = blockedUsers[msg.sender][lastIndex];
            blockedUsers[msg.sender][indexToRemove] = lastUser;
            blockedUserIndex[msg.sender][lastUser] = indexToRemove;
        }
        
        blockedUsers[msg.sender].pop();
        delete blockedUserIndex[msg.sender][_userToUnblock];
        
        emit UserUnblocked(msg.sender, _userToUnblock);
    }

    function getBlockedUsers() public view returns (
        address[] memory blockedAddresses,
        string[] memory usernames,
        string[] memory avatars
    ) {
        address[] storage blocked = blockedUsers[msg.sender];
        uint256 length = blocked.length;
        
        blockedAddresses = new address[](length);
        usernames = new string[](length);
        avatars = new string[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address blockedUser = blocked[i];
            blockedAddresses[i] = blockedUser;
            
            (string memory username, string memory avatar, , , , , , , , , bool exists) = profileContract.users(blockedUser);
            if (exists) {
                usernames[i] = username;
                avatars[i] = avatar;
            } else {
                usernames[i] = string(abi.encodePacked("User ", _addressToString(blockedUser)));
                avatars[i] = "";
            }
        }
    }

    function isUserBlocked(address _user) public view returns (bool) {
        return isBlocked[msg.sender][_user];
    }

    function deleteChat(address _otherUser) public {
        bytes32 chatId = getChatId(msg.sender, _otherUser);
        require(chats[chatId].exists, "Chat does not exist");
        
        chatDeleted[msg.sender][chatId] = true;
        
        emit ChatDeleted(msg.sender, _otherUser, chatId);
    }

    function sendMessage(
        address _recipient,
        string memory _content,
        string memory _imageUrl,
        MessageType _messageType
    ) public userExists(msg.sender) notBlocked(_recipient) hasNotBlockedRecipient(_recipient) {
        require(_recipient != msg.sender, "Cannot message yourself");
        require(
            bytes(_content).length > 0 || bytes(_imageUrl).length > 0 || _messageType == MessageType.TIP,
            "Message must have content, image, or be a tip"
        );

        bytes32 chatId = getChatId(msg.sender, _recipient);
        
        if (!chats[chatId].exists) {
            _createChat(msg.sender, _recipient, chatId);
        }

        if (chatDeleted[msg.sender][chatId]) {
            chatDeleted[msg.sender][chatId] = false;
        }
        if (chatDeleted[_recipient][chatId]) {
            chatDeleted[_recipient][chatId] = false;
        }

        Message memory newMessage = Message({
            id: totalMessages,
            sender: msg.sender,
            recipient: _recipient,
            content: _content,
            imageUrl: _imageUrl,
            tipAmount: 0,
            timestamp: block.timestamp,
            messageType: _messageType,
            exists: true
        });

        chatMessages[chatId].push(newMessage);
        totalMessages++;

        chats[chatId].messageCount++;
        chats[chatId].lastMessageTimestamp = block.timestamp;
        chats[chatId].lastMessageContent = _content;

        emit MessageSent(
            msg.sender,
            _recipient,
            _content,
            _imageUrl,
            0,
            _messageType,
            block.timestamp
        );
    }

    function sendTip(
        address _recipient,
        string memory _message
    ) public payable userExists(msg.sender) notBlocked(_recipient) hasNotBlockedRecipient(_recipient) {
        require(_recipient != msg.sender, "Cannot tip yourself");
        require(msg.value > 0, "Tip amount must be greater than 0");

        bytes32 chatId = getChatId(msg.sender, _recipient);
        
        if (!chats[chatId].exists) {
            _createChat(msg.sender, _recipient, chatId);
        }

        if (chatDeleted[msg.sender][chatId]) {
            chatDeleted[msg.sender][chatId] = false;
        }
        if (chatDeleted[_recipient][chatId]) {
            chatDeleted[_recipient][chatId] = false;
        }

        Message memory newMessage = Message({
            id: totalMessages,
            sender: msg.sender,
            recipient: _recipient,
            content: _message,
            imageUrl: "",
            tipAmount: msg.value,
            timestamp: block.timestamp,
            messageType: MessageType.TIP,
            exists: true
        });

        chatMessages[chatId].push(newMessage);
        totalMessages++;

        chats[chatId].messageCount++;
        chats[chatId].lastMessageTimestamp = block.timestamp;
        chats[chatId].lastMessageContent = string(abi.encodePacked("Sent ", _formatAmount(msg.value), " FMS"));

        (bool success, ) = payable(_recipient).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit MessageSent(
            msg.sender,
            _recipient,
            _message,
            "",
            msg.value,
            MessageType.TIP,
            block.timestamp
        );
    }

    function _createChat(address user1, address user2, bytes32 chatId) internal {
        chats[chatId] = Chat({
            user1: user1,
            user2: user2,
            messageCount: 0,
            lastMessageTimestamp: block.timestamp,
            lastMessageContent: "",
            exists: true
        });

        if (!hasActiveChat[user1][user2]) {
            userChats[user1].push(chatId);
            hasActiveChat[user1][user2] = true;
        }
        
        if (!hasActiveChat[user2][user1]) {
            userChats[user2].push(chatId);
            hasActiveChat[user2][user1] = true;
        }

        emit ChatCreated(user1, user2, chatId);
    }

    function getMessages(
        address _otherUser,
        uint256 _offset,
        uint256 _limit
    ) public view returns (
        address[] memory senders,
        address[] memory recipients,
        string[] memory contents,
        string[] memory imageUrls,
        uint256[] memory tipAmounts,
        uint256[] memory messageTypes,
        uint256[] memory timestamps
    ) {
        bytes32 chatId = getChatId(msg.sender, _otherUser);
        
        if (chatDeleted[msg.sender][chatId]) {
            return (new address[](0), new address[](0), new string[](0), new string[](0), new uint256[](0), new uint256[](0), new uint256[](0));
        }
        
        Message[] storage messages = chatMessages[chatId];
        
        uint256 totalMsgs = messages.length;
        if (_offset >= totalMsgs) {
            return (new address[](0), new address[](0), new string[](0), new string[](0), new uint256[](0), new uint256[](0), new uint256[](0));
        }

        uint256 endIndex = _offset + _limit;
        if (endIndex > totalMsgs) {
            endIndex = totalMsgs;
        }
        
        uint256 resultLength = endIndex - _offset;
        
        senders = new address[](resultLength);
        recipients = new address[](resultLength);
        contents = new string[](resultLength);
        imageUrls = new string[](resultLength);
        tipAmounts = new uint256[](resultLength);
        messageTypes = new uint256[](resultLength);
        timestamps = new uint256[](resultLength);
        
        _populateMessageArrays(
            messages,
            _offset,
            resultLength,
            senders,
            recipients,
            contents,
            imageUrls,
            tipAmounts,
            messageTypes,
            timestamps
        );
    }

    function _populateMessageArrays(
        Message[] storage messages,
        uint256 offset,
        uint256 length,
        address[] memory senders,
        address[] memory recipients,
        string[] memory contents,
        string[] memory imageUrls,
        uint256[] memory tipAmounts,
        uint256[] memory messageTypes,
        uint256[] memory timestamps
    ) internal view {
        for (uint256 i = 0; i < length; i++) {
            Message storage currentMsg = messages[offset + i];
            senders[i] = currentMsg.sender;
            recipients[i] = currentMsg.recipient;
            contents[i] = currentMsg.content;
            imageUrls[i] = currentMsg.imageUrl;
            tipAmounts[i] = currentMsg.tipAmount;
            messageTypes[i] = uint256(currentMsg.messageType);
            timestamps[i] = currentMsg.timestamp;
        }
    }

    function getMessageCount(address _otherUser) public view returns (uint256) {
        bytes32 chatId = getChatId(msg.sender, _otherUser);
        
        if (chatDeleted[msg.sender][chatId]) {
            return 0;
        }
        
        return chatMessages[chatId].length;
    }

    function getUserChats() public view returns (
        address[] memory chatPartners,
        string[] memory usernames,
        string[] memory avatars,
        string[] memory lastMessages,
        uint256[] memory lastTimestamps
    ) {
        bytes32[] storage userChatIds = userChats[msg.sender];
        
        uint256 activeChatsCount = 0;
        for (uint256 i = 0; i < userChatIds.length; i++) {
            if (!chatDeleted[msg.sender][userChatIds[i]]) {
                activeChatsCount++;
            }
        }
        
        chatPartners = new address[](activeChatsCount);
        usernames = new string[](activeChatsCount);
        avatars = new string[](activeChatsCount);
        lastMessages = new string[](activeChatsCount);
        lastTimestamps = new uint256[](activeChatsCount);
        
        uint256 activeIndex = 0;
        for (uint256 i = 0; i < userChatIds.length; i++) {
            bytes32 chatId = userChatIds[i];
            
            if (chatDeleted[msg.sender][chatId]) {
                continue;
            }
            
            Chat storage chat = chats[chatId];
            address partner = chat.user1 == msg.sender ? chat.user2 : chat.user1;
            
            chatPartners[activeIndex] = partner;
            lastMessages[activeIndex] = chat.lastMessageContent;
            lastTimestamps[activeIndex] = chat.lastMessageTimestamp;
            
            (string memory username, string memory avatar, , , , , , , , , bool exists) = profileContract.users(partner);
            if (exists) {
                usernames[activeIndex] = username;
                avatars[activeIndex] = avatar;
            } else {
                usernames[activeIndex] = string(abi.encodePacked("User ", _addressToString(partner)));
                avatars[activeIndex] = "";
            }
            
            activeIndex++;
        }
    }

    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        uint256 fms = amount / 1e14; 
        return string(abi.encodePacked(_uint2str(fms / 10000), ".", _uint2str((fms % 10000) / 1000), _uint2str((fms % 1000) / 100), _uint2str((fms % 100) / 10), _uint2str(fms % 10)));
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}
