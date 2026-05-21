// =========================================
/*
████████╗██╗██████╗
╚══██╔══╝██║██╔══██╗
   ██║   ██║██████╔╝     T I P
   ██║   ██║██╔═══╝      Decentralized On-Chain Forms
   ██║   ██║██║          https://tip.lat
   ╚═╝   ╚═╝╚═╝
*/
// =========================================

/**
 * @title TIPForms
 * @notice Decentralized on-chain forms protocol by TIP
 * @dev Core contract for TIP ecosystem
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract TIPForms {


    address public owner;
    address public treasury;   
    uint256 public creationFee;
    uint256 public formCount;

    struct Form {
        uint256 id;
        address creator;
        string  title;
        string  description;
        string  fields;            
        uint256 expiration;        
        bool    active;
        bool    preventDuplicates; 
        uint256 createdAt;
        uint256 responseCount;
    }

    struct Response {
        address responder;
        string  cid;
        uint256 timestamp;
    }

    mapping(uint256 => Form)                        public  forms;
    mapping(uint256 => Response[])                  private _responses;
    mapping(uint256 => mapping(address => bool))    public  hasSubmitted;


    event FormCreated(uint256 indexed formId, address indexed creator, string title);
    event FormSubmitted(uint256 indexed formId, address indexed responder, string cid);
    event FormClosed(uint256 indexed formId);
    event FeeUpdated(uint256 newFee);
    event TreasuryUpdated(address indexed newTreasury);


    constructor(uint256 _creationFee, address _treasury) {
        require(_treasury != address(0), "TIPForms: invalid treasury");

        owner        = msg.sender;
        creationFee  = _creationFee;
        treasury     = _treasury;
    }


    modifier onlyOwner() {
        require(msg.sender == owner, "TIPForms: not owner");
        _;
    }

    modifier validForm(uint256 _formId) {
        require(_formId > 0 && _formId <= formCount, "TIPForms: form does not exist");
        _;
    }

  
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "TIPForms: zero address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setCreationFee(uint256 _fee) external onlyOwner {
        creationFee = _fee;
        emit FeeUpdated(_fee);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "TIPForms: zero address");
        owner = _newOwner;
    }

  
    function createForm(
        string calldata _title,
        string calldata _description,
        string calldata _fields,
        uint256 _expiration,
        bool    _preventDuplicates
    ) external payable {
        // ── Fee validation ────────────────────────────────────────────────────
        require(msg.value >= creationFee,  "TIPForms: insufficient fee");
        require(bytes(_title).length  > 0, "TIPForms: title required");
        require(bytes(_fields).length > 0, "TIPForms: fields required");
        require(
            _expiration == 0 || _expiration > block.timestamp,
            "TIPForms: expiration in the past"
        );

        // ── Forward fee to treasury (no ETH left in contract) ─────────────────
        (bool sent, ) = payable(treasury).call{value: msg.value}("");
        require(sent, "TIPForms: fee transfer failed");

        // ── Store form ────────────────────────────────────────────────────────
        formCount++;

        forms[formCount] = Form({
            id:                formCount,
            creator:           msg.sender,
            title:             _title,
            description:       _description,
            fields:            _fields,
            expiration:        _expiration,
            active:            true,
            preventDuplicates: _preventDuplicates,
            createdAt:         block.timestamp,
            responseCount:     0
        });

        emit FormCreated(formCount, msg.sender, _title);
    }

  
    function submitResponse(uint256 _formId, string calldata _cid)
        external
        validForm(_formId)
    {
        Form storage form = forms[_formId];

        require(form.active,                "TIPForms: form is closed");
        require(bytes(_cid).length > 0,     "TIPForms: CID required");
        require(
            form.expiration == 0 || block.timestamp <= form.expiration,
            "TIPForms: form has expired"
        );

        if (form.preventDuplicates) {
            require(!hasSubmitted[_formId][msg.sender], "TIPForms: already submitted");
            hasSubmitted[_formId][msg.sender] = true;
        }

        _responses[_formId].push(Response({
            responder: msg.sender,
            cid:       _cid,
            timestamp: block.timestamp
        }));

        form.responseCount++;

        emit FormSubmitted(_formId, msg.sender, _cid);
    }

  
    function closeForm(uint256 _formId) external validForm(_formId) {
        require(forms[_formId].creator == msg.sender, "TIPForms: not creator");
        require(forms[_formId].active,                "TIPForms: already closed");
        forms[_formId].active = false;
        emit FormClosed(_formId);
    }


    function getFormResponses(uint256 _formId)
        external
        view
        validForm(_formId)
        returns (Response[] memory)
    {
        return _responses[_formId];
    }

    function getCreatorForms(address _creator)
        external
        view
        returns (uint256[] memory)
    {
        uint256 count;
        for (uint256 i = 1; i <= formCount; i++) {
            if (forms[i].creator == _creator) count++;
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx;
        for (uint256 i = 1; i <= formCount; i++) {
            if (forms[i].creator == _creator) ids[idx++] = i;
        }

        return ids;
    }

  
    receive() external payable {
        revert("TIPForms: use createForm()");
    }
}
