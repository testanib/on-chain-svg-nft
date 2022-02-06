// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "base64-sol/base64.sol";


contract RandomOnChainSVG is ERC721URIStorage, IERC2981, VRFConsumerBase, Ownable {
    bytes32 public keyHash;
    uint256 public fee;
    uint256 public tokenCounter;
    uint256 public price = 10000000000000000; // .01 ETH
    address public _recipient;
    uint256 public maxAmount = 50;

    //SVG Params
    uint256 public immutable maxPaths = 20;
    uint256 public immutable maxPathCommands = 10;
    uint256 public immutable size = 1000;
    string[] public pathCommands = ["M", "L"];
    string[] public colors = ["red", "green", "blue", "black", "purple", "orange", "brown", "magenta"];

    mapping(bytes32 => address) internal requestIdToSender;
    mapping(bytes32 => uint256) internal requestIdToTokenId;
    mapping(uint256 => uint256) internal tokenIdToRandomNumber;
    mapping(uint256 => address) internal tokenIdToRecipient;

    /**
     * @dev indexed values are treated as log topics instead of raw data.
     * @dev Allows you to search for specific events rather than parsing the entire log.
     */
    event requestedRandomSVG(bytes32 indexed requestId, uint256 indexed tokenId);
    event createdUnfinishedSVG(uint256 indexed tokenId, uint256 indexed randomNumber);
    event createdRandomSVG(uint256 indexed tokenId, string tokenURI);


    /**
        * @dev Constructor
        * @param _VRFCoordinator address of the VRF coordinator
        * @param _LinkToken address of the Link token
        * @param _keyHash bytes32 
        * @param _fee uint256 
     */
    constructor(address _VRFCoordinator, address _LinkToken, bytes32 _keyHash, uint256 _fee) 
    VRFConsumerBase(_VRFCoordinator, _LinkToken)
    ERC721("RandomOnChainSVG", "ROSVG")
    {
        keyHash = _keyHash;
        fee = _fee;
        tokenCounter = 0;
        _recipient = owner();
    }

    /**
        Modifier to handle require statements for minting
     */
    modifier mintCompliance(uint256 value, uint256 numTokens) {
        require(msg.value >= price * numTokens, "Insufficient funds");
        require(tokenCounter + numTokens <= maxAmount, "Cannot exceed max amount");
        _;
    }


    /**
        Function to handle changing the VRF coordinator fee
     */
    function setVRFFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    /**
     * @dev allows the owner to withdraw funds
     */
    function withdraw() public payable onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }


    /**
        * @dev Requests ChainLink VRF number and maps the id
        * Technically this is the NFT
     */
    function create() public payable mintCompliance(msg.value, 1) returns (bytes32 requestId){
        requestId = requestRandomness(keyHash, fee);
        requestIdToSender[requestId] = msg.sender;
        uint256 tokenId = tokenCounter; 
        requestIdToTokenId[requestId] = tokenId;
        tokenCounter = tokenCounter + 1;
        tokenIdToRecipient[tokenId] = msg.sender;
        emit requestedRandomSVG(requestId, tokenId);
    }

    function devMint(uint256 quantity) external onlyOwner returns(bytes32 requestId){
        for (uint256 i = 0; i < quantity; i++) {
            requestId = requestRandomness(keyHash, fee);
            requestIdToSender[requestId] = msg.sender;
            uint256 tokenId = tokenCounter; 
            requestIdToTokenId[requestId] = tokenId;
            tokenCounter = tokenCounter + 1;
            tokenIdToRecipient[tokenId] = msg.sender;
            emit requestedRandomSVG(requestId, tokenId);
        }
    }

    /**
        * @dev Mint multiple NFTs
        * Can potentially be optimized with ERC721A but this contract is already at its size limit
     */
    function createtBatch(uint256 numTokens) public payable mintCompliance(msg.value, numTokens) returns (bytes32 requestId){
        require(numTokens > 1 && numTokens < 10,"Invalid Mint Batch Mint Amount");
        for (uint256 i; i < numTokens; i++) {
            create();
        }
    }


    /** 
        * @dev Overriden fulfillRandomness function to fulfill the request
        * @param requestId VRF request ID
        * @param randomNumber VRF random number
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomNumber) internal override {
        address sender = requestIdToSender[requestId];
        uint256 tokenId = requestIdToTokenId[requestId];
        _safeMint(sender, tokenId);
        tokenIdToRandomNumber[tokenId] = randomNumber;
        emit createdUnfinishedSVG(tokenId, randomNumber);
    }


    /**
        * @dev Savs generated SVG info to the blockchain
        * @param _tokenId Token ID
        * Requires: 
        *   - tokenId is a valid token ID
        *   - tokenIdToRandomNumber[tokenId] is a valid random number
        *   - tokenCounter is greater than tokenId
     */
    function finishMint(uint256 _tokenId) public {
        require(bytes(tokenURI(_tokenId)).length <= 0, "tokenURI is already set");
        require(tokenCounter > _tokenId, "tokenId is not valid");
        require(tokenIdToRandomNumber[_tokenId] > 0, "need to wait for ChainLink VRF");
        require(tokenIdToRecipient[_tokenId] == msg.sender, "Only the recipient can finish minting");
        uint256 randomNumber = tokenIdToRandomNumber[_tokenId];
        string memory svg = generateSVG(randomNumber);
        string memory imageURI = svgToImageURI(svg);
        _setTokenURI(_tokenId, formatTokenURI(imageURI));
        emit createdRandomSVG(_tokenId, svg);
    }


    //Same as above but for batch minting
    //can only do a max of 7 at once
    function finishMintBatch(uint256 _firstTokenId, uint256 _lastTokenId) public {
        require(_lastTokenId >= _firstTokenId, "lastTokenId must be greater than firstTokenId");
        for(_firstTokenId; _firstTokenId < _lastTokenId; _firstTokenId++) {
            finishMint(_firstTokenId);
        }
    }


    /**
        * @dev Generates SVG outline and calls generatePath to generate each path for the SVG
        * @param _randomNumber VRF random number
     */
    function generateSVG(uint256 _randomNumber) internal view returns (string memory svg) {
        uint256 numPaths = (_randomNumber % maxPaths) + 1;
        svg = string(abi.encodePacked("<svg xmlns='http://www.w3.org/2000/svg' height='", uint2str(size), "' width='", uint2str(size), "'>"));
        for (uint256 i = 0; i < numPaths; i++) {
            string memory pathSVG = generatePath(uint256(keccak256(abi.encodePacked(_randomNumber, i))));
            svg = string(abi.encodePacked(svg, pathSVG));
        }
        svg = string(abi.encodePacked(svg, "</svg>"));
    }


    /**
        * @dev Loops calling generateCommand to generate each path command for the SVG
        * @param _randomNumber VRF random number
     */
    function generatePath(uint256 _randomNumber) internal view returns (string memory pathSvg){
        uint256 numCommands = (_randomNumber % maxPathCommands) + 1;
        pathSvg = "<path d='";
        for (uint256 j = 0; j < numCommands; j++) {
            string memory command = generateCommand(uint256(keccak256(abi.encodePacked(_randomNumber, size + j))));
            pathSvg = string(abi.encodePacked(pathSvg, command));
            
        }
        string memory color = colors[_randomNumber % colors.length];
        pathSvg = string(abi.encodePacked(pathSvg, "' fill='transparent' stroke='", color,"'/>"));
    }


    /**
        * @dev Generates a single random path command using all path options
        * @param _randomNumber VRF random number
     */
    function generateCommand(uint256 _randomNumber) internal view returns (string memory command){
        command = pathCommands[_randomNumber % pathCommands.length];
        uint256 parameterOne = uint256(keccak256(abi.encode(_randomNumber, size * 2))) % size;
        uint256 parameterTwo = uint256(keccak256(abi.encode(_randomNumber, size * 2 + 1))) % size;
        command = string(abi.encodePacked(command, " ", uint2str(parameterOne), " ", uint2str(parameterTwo)));
    }


    /**
        * @dev Converts SVG to image URI with base64 encoding
        * @param svg SVG string
     */
    function svgToImageURI(string memory svg) public pure returns (string memory) {
        return string(abi.encodePacked("data:image/svg+xml;base64,",Base64.encode(bytes(string(abi.encodePacked(svg))))));
    }


    /**
        * @dev Converts image URI to token URI
        * @param imageURI image URI string
     */
    function formatTokenURI(string memory imageURI) public pure returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,",Base64.encode(bytes(
            abi.encodePacked(
                '{"name":"', "Random Generated On-Chain SVG",'", "description":"An NFT based on an SVG that was generated randomly with the help of ChainLink VRF!", "attributes":"", "image":"',imageURI,'"}'
            ))))
        );
    }


    /**
        * @dev Converts uint to a string
        * @param _i uint to be converted
     */
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /**
        * @dev ERC2981 Royalty Token Interface
        * @param _tokenId uint256 Token ID
        * @param _salePrice uint256 Sale price
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        return (_recipient, (_salePrice * 1000) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool){
        return (interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId));
    }

    //can be replaced with counters.sol counters
    function totalSupply() public view returns (uint256) {
      return tokenCounter;
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

}