// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "base64-sol/base64.sol";

contract SVGNFT is ERC721URIStorage, Ownable {
    uint256 public tokenCounter;
    event CreatedSVGNFT(uint256 indexed tokenId, string tokenURI);

    constructor() ERC721("SVG NFT", "svgNFT")
    {
        tokenCounter = 0;
    }

    function create(string memory svg) public {
        _safeMint(msg.sender, tokenCounter);
        string memory imageURI = svgToImageURI(svg);
        string memory tokenURI = formatTokenURI(imageURI);
        _setTokenURI(tokenCounter, tokenURI);
        tokenCounter++;
        emit CreatedSVGNFT(tokenCounter, tokenURI);
    }

    function svgToImageURI(string memory svg) public pure returns (string memory) {
        return string(abi.encodePacked("data:image/svg+xml;base64,",Base64.encode(bytes(string(abi.encodePacked(svg))))));
    }

    function formatTokenURI(string memory imageURI) public pure returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,",Base64.encode(bytes(
            abi.encodePacked(
                '{"name":"', "Basic SVG NFT",'", "description":"An NFT based on an SVG!", "attributes":"", "image":"',imageURI,'"}'
            ))))
        );
    }
}
