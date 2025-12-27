// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IPlantRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract PlantNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Lineage {
        uint256 genes;
        uint256 parentA;
        uint256 parentB;
        uint32 generation;
    }

    uint256 public nextId = 1;
    mapping(uint256 => Lineage) public lineage;

    IPlantRenderer public renderer;

    constructor(string memory name_, string memory symbol_, address admin) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function setRenderer(address r) external onlyRole(DEFAULT_ADMIN_ROLE) {
        renderer = IPlantRenderer(r);
    }

    function mintSeed(address to, uint256 genes) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = nextId++;
        _safeMint(to, tokenId);
        lineage[tokenId] = Lineage({ genes: genes, parentA: 0, parentB: 0, generation: 0 });
    }

    function mintChild(address to, uint256 genes, uint256 parentA, uint256 parentB, uint32 generation)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = nextId++;
        _safeMint(to, tokenId);
        lineage[tokenId] = Lineage({ genes: genes, parentA: parentA, parentB: parentB, generation: generation });
    }

    function genesOf(uint256 tokenId) external view returns (uint256) {
        return lineage[tokenId].genes;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (address(renderer) != address(0)) return renderer.tokenURI(tokenId);
        return "";
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
