// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract TIPSocial {
    struct User {
        string username;
        string avatar;
        string banner;
        string bio;
        string website;
        uint32 postCount;
        uint32 followerCount;
        uint32 followingCount;
        uint256 totalTipsReceived;
        uint256 totalTipsSent;
        bool exists;
    }

    struct Post {
        uint32 id;
        address author;
        string content;
        string imageUrl;
        uint32 timestamp;
        uint32 likeCount;
        uint32 commentCount;
        uint32 repostCount;
        uint256 tipAmount;
        uint32 tipCount;
        bool exists;
    }

    struct Comment {
        uint32 id;
        uint32 postId;
        address author;
        string content;
        string imageUrl;
        uint32 timestamp;
        bool exists;
    }

    // ── Social mappings ──────────────────────────────────────────────────────
    mapping(address => User) public users;
    mapping(string => address) public usernameToAddress;
    mapping(uint256 => Post) public posts;
    mapping(uint256 => Comment) public comments;
    mapping(address => mapping(address => bool)) public following;
    mapping(address => mapping(uint256 => bool)) public userLikedPost;
    mapping(address => mapping(uint256 => bool)) public userRepostedPost;
    mapping(address => uint256[]) public userPosts;
    mapping(uint256 => uint256[]) public postComments;

    uint32 public postCount;
    uint32 public commentCount;

    // ── Stories mappings ─────────────────────────────────────────────────────
    mapping(address => uint256) public storyCount;
    mapping(address => mapping(string => uint256)) public reactionCount;

    // ── Social events ────────────────────────────────────────────────────────
    event UserCreated(address indexed user, string username);
    event UserUpdated(
        address indexed user,
        string username,
        string avatar,
        string banner,
        string bio,
        string website
    );
    event PostCreated(
        uint256 indexed postId,
        address indexed author,
        string content,
        string imageUrl
    );
    event PostLiked(uint256 indexed postId, address indexed liker);
    event PostUnliked(uint256 indexed postId, address indexed unliker);
    event CommentAdded(
        uint256 indexed commentId,
        uint256 indexed postId,
        address indexed author,
        string content,
        string imageUrl
    );
    event PostReposted(uint256 indexed postId, address indexed reposter);
    event PostUnreposted(uint256 indexed postId, address indexed unreposter);
    event UserFollowed(address indexed follower, address indexed followed);
    event UserUnfollowed(address indexed follower, address indexed unfollowed);
    event TipSent(
        uint256 indexed tipId,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 postId,
        string message
    );

    // ── Stories events ───────────────────────────────────────────────────────
    event StoryPosted(
        address indexed user,
        string  cid,
        uint256 createdAt
    );
    event StoryReaction(
        address indexed reactor,
        address indexed storyAuthor,
        string  cid,
        string  emoji,
        uint256 createdAt
    );

    // ── Modifiers ────────────────────────────────────────────────────────────
    modifier userExists(address _user) {
        require(users[_user].exists, "User not found");
        _;
    }

    modifier postExists(uint256 _postId) {
        require(posts[_postId].exists, "Post not found");
        _;
    }

    // ── User functions ───────────────────────────────────────────────────────
    function createUser(
        string memory _username,
        string memory _avatar
    ) external {
        require(!users[msg.sender].exists, "User exists");
        require(bytes(_username).length > 0, "Empty username");
        require(usernameToAddress[_username] == address(0), "Username taken");

        users[msg.sender] = User({
            username: _username,
            avatar: _avatar,
            banner: "",
            bio: "",
            website: "",
            postCount: 0,
            followerCount: 0,
            followingCount: 0,
            totalTipsReceived: 0,
            totalTipsSent: 0,
            exists: true
        });

        usernameToAddress[_username] = msg.sender;
        emit UserCreated(msg.sender, _username);
    }

    function updateUser(
        string memory _username,
        string memory _avatar
    ) external userExists(msg.sender) {
        require(bytes(_username).length > 0, "Empty username");

        if (
            keccak256(bytes(users[msg.sender].username)) !=
            keccak256(bytes(_username))
        ) {
            require(
                usernameToAddress[_username] == address(0),
                "Username taken"
            );
            delete usernameToAddress[users[msg.sender].username];
            usernameToAddress[_username] = msg.sender;
        }

        users[msg.sender].username = _username;
        users[msg.sender].avatar = _avatar;
        emit UserUpdated(
            msg.sender,
            _username,
            _avatar,
            users[msg.sender].banner,
            users[msg.sender].bio,
            users[msg.sender].website
        );
    }

    function updateUserBanner(
        string memory _banner
    ) external userExists(msg.sender) {
        users[msg.sender].banner = _banner;
        emit UserUpdated(
            msg.sender,
            users[msg.sender].username,
            users[msg.sender].avatar,
            _banner,
            users[msg.sender].bio,
            users[msg.sender].website
        );
    }

    function updateUserBio(string memory _bio) external userExists(msg.sender) {
        users[msg.sender].bio = _bio;
        emit UserUpdated(
            msg.sender,
            users[msg.sender].username,
            users[msg.sender].avatar,
            users[msg.sender].banner,
            _bio,
            users[msg.sender].website
        );
    }

    function updateUserWebsite(
        string memory _website
    ) external userExists(msg.sender) {
        users[msg.sender].website = _website;
        emit UserUpdated(
            msg.sender,
            users[msg.sender].username,
            users[msg.sender].avatar,
            users[msg.sender].banner,
            users[msg.sender].bio,
            _website
        );
    }

    function updateUserProfile(
        string memory _username,
        string memory _avatar,
        string memory _banner
    ) external userExists(msg.sender) {
        require(bytes(_username).length > 0, "Empty username");

        if (
            keccak256(bytes(users[msg.sender].username)) !=
            keccak256(bytes(_username))
        ) {
            require(
                usernameToAddress[_username] == address(0),
                "Username taken"
            );
            delete usernameToAddress[users[msg.sender].username];
            usernameToAddress[_username] = msg.sender;
        }

        users[msg.sender].username = _username;
        users[msg.sender].avatar = _avatar;
        users[msg.sender].banner = _banner;
        emit UserUpdated(
            msg.sender,
            _username,
            _avatar,
            _banner,
            users[msg.sender].bio,
            users[msg.sender].website
        );
    }

    function updateFullUserProfile(
        string memory _username,
        string memory _avatar,
        string memory _banner,
        string memory _bio,
        string memory _website
    ) external userExists(msg.sender) {
        require(bytes(_username).length > 0, "Empty username");

        if (
            keccak256(bytes(users[msg.sender].username)) !=
            keccak256(bytes(_username))
        ) {
            require(
                usernameToAddress[_username] == address(0),
                "Username taken"
            );
            delete usernameToAddress[users[msg.sender].username];
            usernameToAddress[_username] = msg.sender;
        }

        users[msg.sender].username = _username;
        users[msg.sender].avatar = _avatar;
        users[msg.sender].banner = _banner;
        users[msg.sender].bio = _bio;
        users[msg.sender].website = _website;
        emit UserUpdated(
            msg.sender,
            _username,
            _avatar,
            _banner,
            _bio,
            _website
        );
    }

    function getAddressByUsername(
        string memory _username
    ) external view returns (address) {
        return usernameToAddress[_username];
    }

    // ── Post functions ───────────────────────────────────────────────────────
    function createPost(
        string memory _content,
        string memory _imageUrl
    ) external userExists(msg.sender) {
        require(
            bytes(_content).length > 0 || bytes(_imageUrl).length > 0,
            "Empty post"
        );

        uint32 newPostId = postCount;
        posts[newPostId] = Post({
            id: newPostId,
            author: msg.sender,
            content: _content,
            imageUrl: _imageUrl,
            timestamp: uint32(block.timestamp),
            likeCount: 0,
            commentCount: 0,
            repostCount: 0,
            tipAmount: 0,
            tipCount: 0,
            exists: true
        });

        userPosts[msg.sender].push(newPostId);
        users[msg.sender].postCount++;
        postCount++;
        emit PostCreated(newPostId, msg.sender, _content, _imageUrl);
    }

    function likePost(
        uint256 _postId
    ) external userExists(msg.sender) postExists(_postId) {
        require(!userLikedPost[msg.sender][_postId], "Already liked");

        userLikedPost[msg.sender][_postId] = true;
        posts[_postId].likeCount++;
        emit PostLiked(_postId, msg.sender);
    }

    function unlikePost(
        uint256 _postId
    ) external userExists(msg.sender) postExists(_postId) {
        require(userLikedPost[msg.sender][_postId], "Not liked");

        userLikedPost[msg.sender][_postId] = false;
        posts[_postId].likeCount--;
        emit PostUnliked(_postId, msg.sender);
    }

    function commentOnPost(
        uint256 _postId,
        string memory _content,
        string memory _imageUrl
    ) external userExists(msg.sender) postExists(_postId) {
        require(
            bytes(_content).length > 0 || bytes(_imageUrl).length > 0,
            "Empty comment"
        );

        uint32 newCommentId = commentCount;
        comments[newCommentId] = Comment({
            id: newCommentId,
            postId: uint32(_postId),
            author: msg.sender,
            content: _content,
            imageUrl: _imageUrl,
            timestamp: uint32(block.timestamp),
            exists: true
        });

        postComments[_postId].push(newCommentId);
        posts[_postId].commentCount++;
        commentCount++;
        emit CommentAdded(
            newCommentId,
            _postId,
            msg.sender,
            _content,
            _imageUrl
        );
    }

    function repostPost(
        uint256 _postId
    ) external userExists(msg.sender) postExists(_postId) {
        require(!userRepostedPost[msg.sender][_postId], "Already reposted");
        require(posts[_postId].author != msg.sender, "Own post");

        userRepostedPost[msg.sender][_postId] = true;
        posts[_postId].repostCount++;
        emit PostReposted(_postId, msg.sender);
    }

    function unrepostPost(
        uint256 _postId
    ) external userExists(msg.sender) postExists(_postId) {
        require(userRepostedPost[msg.sender][_postId], "Not reposted");

        userRepostedPost[msg.sender][_postId] = false;
        posts[_postId].repostCount--;
        emit PostUnreposted(_postId, msg.sender);
    }

    // ── Tip functions ────────────────────────────────────────────────────────
    function tipUser(
        address _to,
        uint256 _amount,
        string memory _message
    ) external payable userExists(msg.sender) userExists(_to) {
        require(_to != msg.sender, "Self tip");
        require(msg.value > 0, "Tip amount must be greater than 0");
        require(msg.value == _amount, "Amount mismatch");

        users[msg.sender].totalTipsSent += msg.value;
        users[_to].totalTipsReceived += msg.value;

        (bool success, ) = payable(_to).call{value: msg.value}("");
        require(success, "Transfer failed");
        emit TipSent(0, msg.sender, _to, msg.value, 0, _message);
    }

    function tipPost(
        uint256 _postId,
        uint256 _amount,
        string memory _message
    ) external payable userExists(msg.sender) postExists(_postId) {
        require(posts[_postId].author != msg.sender, "Own post");
        require(msg.value > 0, "Tip amount must be greater than 0");
        require(msg.value == _amount, "Amount mismatch");

        address postAuthor = posts[_postId].author;
        users[msg.sender].totalTipsSent += msg.value;
        users[postAuthor].totalTipsReceived += msg.value;
        posts[_postId].tipAmount += msg.value;
        posts[_postId].tipCount++;

        (bool success, ) = payable(postAuthor).call{value: msg.value}("");
        require(success, "Transfer failed");
        emit TipSent(0, msg.sender, postAuthor, msg.value, _postId, _message);
    }

    // ── Follow functions ─────────────────────────────────────────────────────
    function followUser(
        address _user
    ) external userExists(msg.sender) userExists(_user) {
        require(msg.sender != _user, "Self follow");
        require(!following[msg.sender][_user], "Already following");

        following[msg.sender][_user] = true;
        users[msg.sender].followingCount++;
        users[_user].followerCount++;
        emit UserFollowed(msg.sender, _user);
    }

    function unfollowUser(
        address _user
    ) external userExists(msg.sender) userExists(_user) {
        require(following[msg.sender][_user], "Not following");

        following[msg.sender][_user] = false;
        users[msg.sender].followingCount--;
        users[_user].followerCount--;
        emit UserUnfollowed(msg.sender, _user);
    }

    // ── Stories functions ────────────────────────────────────────────────────
    /// @notice Post a story — requires a registered profile.
    function postStory(string calldata cid) external userExists(msg.sender) {
        require(bytes(cid).length > 0, "CID required");
        storyCount[msg.sender]++;
        emit StoryPosted(msg.sender, cid, block.timestamp);
    }

    /// @notice React to a story with an emoji — requires a registered profile.
    function reactToStory(
        address storyAuthor,
        string calldata cid,
        string calldata emoji
    ) external userExists(msg.sender) {
        require(bytes(cid).length > 0,   "CID required");
        require(bytes(emoji).length > 0, "Emoji required");
        reactionCount[storyAuthor][cid]++;
        emit StoryReaction(msg.sender, storyAuthor, cid, emoji, block.timestamp);
    }

    // ── View functions ───────────────────────────────────────────────────────
    function getUserPosts(
        address _user
    ) external view returns (uint256[] memory) {
        return userPosts[_user];
    }

    function getPostComments(
        uint256 _postId
    ) external view returns (uint256[] memory) {
        return postComments[_postId];
    }

    function getUserTipsReceived(
        address /* _user */
    ) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function getUserTipsSent(
        address /* _user */
    ) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function getPostTips(
        uint256 /* _postId */
    ) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function isFollowing(
        address _follower,
        address _followed
    ) external view returns (bool) {
        return following[_follower][_followed];
    }

    function hasLikedPost(
        address _user,
        uint256 _postId
    ) external view returns (bool) {
        return userLikedPost[_user][_postId];
    }

    function hasRepostedPost(
        address _user,
        uint256 _postId
    ) external view returns (bool) {
        return userRepostedPost[_user][_postId];
    }
}
