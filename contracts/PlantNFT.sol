// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/contracts/token/ERC721/ERC721.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/contracts/access/AccessControl.sol";

interface IPlantRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract PlantNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /* 0 = FEMALE, 1 = MALE */
    enum Sex {
        FEMALE,
        MALE
    }

    struct Lineage {
        uint256 genes;
        uint256 parentA;
        uint256 parentB;
        uint32 generation;
    }

    uint256 public nextId = 1;
    mapping(uint256 => Lineage) public lineage;

    IPlantRenderer public renderer;

    uint256 public constant MAX_BATCH = 300;

    event RendererSet(address indexed renderer);
    event SeedMinted(address indexed to, uint256 indexed tokenId, uint256 genes);

    event SeedsBatchMinted(
        address indexed to,
        uint256 startId,
        uint256 count,
        uint256 femaleCount,
        uint256 maleCount
    );

    constructor(string memory name_, string memory symbol_, address admin) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function setRenderer(address r) external onlyRole(DEFAULT_ADMIN_ROLE) {
        renderer = IPlantRenderer(r);
        emit RendererSet(r);
    }



    function mintSeed(address to, uint256 genes)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = _mintSeedInternal(to, genes);
    }

    function mintChild(
        address to,
        uint256 genes,
        uint256 parentA,
        uint256 parentB,
        uint32 generation
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = nextId++;
        _safeMint(to, tokenId);
        lineage[tokenId] = Lineage({
            genes: genes,
            parentA: parentA,
            parentB: parentB,
            generation: generation
        });
    }


    function mintSeedBatchExact(address to, uint256[] calldata genesList)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 startId)
    {
        uint256 count = genesList.length;
        _requireBatchBasics(to, count);

        startId = nextId;

        uint256 femaleCount = _batchExactCalldata(to, genesList);
        uint256 maleCount = count - femaleCount;

        emit SeedsBatchMinted(to, startId, count, femaleCount, maleCount);
    }

    function mintSeedBatchWithSexRatio(
        address to,
        uint256[] calldata genesList,
        uint16 femaleBps,
        bytes32 salt
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 startId)
    {
        uint256 count = genesList.length;
        _requireBatchBasics(to, count);
        require(femaleBps <= 10_000, "PlantNFT: bad bps");

        startId = nextId;

        bytes32 base = keccak256(
            abi.encode(block.prevrandao, block.timestamp, msg.sender, to, salt, startId)
        );

        uint256[] memory memGenes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            memGenes[i] = genesList[i];
        }

        uint256 femaleCount = _batchWithRatioMem(to, memGenes, femaleBps, base);
        uint256 maleCount = count - femaleCount;

        emit SeedsBatchMinted(to, startId, count, femaleCount, maleCount);
    }

    function mintSeedBatchByTemplate(
        address to,
        uint256[] calldata genesTemplates,
        uint32[] calldata qtys,
        uint16 femaleBps,
        bytes32 salt
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 startId)
    {
        require(to != address(0), "PlantNFT: to=0");
        require(genesTemplates.length == qtys.length, "PlantNFT: len mismatch");
        require(femaleBps <= 10_000, "PlantNFT: bad bps");

        uint256 total = 0;
        for (uint256 i = 0; i < qtys.length; i++) {
            total += uint256(qtys[i]);
        }
        _requireBatchBasics(to, total);

        startId = nextId;

        uint256[] memory expanded = new uint256[](total);
        uint256 k = 0;
        for (uint256 i = 0; i < genesTemplates.length; i++) {
            uint256 g = genesTemplates[i];
            uint256 q = uint256(qtys[i]);
            for (uint256 j = 0; j < q; j++) {
                expanded[k] = g;
                unchecked { k++; }
            }
        }

        bytes32 base = keccak256(
            abi.encode(block.prevrandao, block.timestamp, msg.sender, to, salt, startId)
        );

        uint256 femaleCount = _batchWithRatioMem(to, expanded, femaleBps, base);
        uint256 maleCount = total - femaleCount;

        emit SeedsBatchMinted(to, startId, total, femaleCount, maleCount);
    }


    function genesOf(uint256 tokenId) external view returns (uint256) {
        return lineage[tokenId].genes;
    }

    /// @notice Sex derived from genes: trait0 even=FEMALE, odd=MALE
    function sexOf(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return _sexFromGenes(lineage[tokenId].genes);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (address(renderer) != address(0)) return renderer.tokenURI(tokenId);
        return "";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


    function _requireBatchBasics(address to, uint256 n) internal pure {
        require(to != address(0), "PlantNFT: to=0");
        require(n > 0, "PlantNFT: empty");
        require(n <= MAX_BATCH, "PlantNFT: too many");
    }

    function _mintSeedInternal(address to, uint256 genes) internal returns (uint256 tokenId) {
        tokenId = nextId++;
        _safeMint(to, tokenId);
        lineage[tokenId] = Lineage({ genes: genes, parentA: 0, parentB: 0, generation: 0 });
        emit SeedMinted(to, tokenId, genes);
    }

    function _sexFromGenes(uint256 genes) internal pure returns (uint8) {
        uint16 trait0 = uint16(genes & 0xFFFF);
        return (trait0 & 1) == 0 ? uint8(Sex.FEMALE) : uint8(Sex.MALE);
    }

    function _setSexInGenes(uint256 genes, uint8 desiredSex) internal pure returns (uint256) {
        uint16 trait0 = uint16(genes & 0xFFFF);
        uint8 currentSex = (trait0 & 1) == 0 ? uint8(Sex.FEMALE) : uint8(Sex.MALE);
        if (currentSex == desiredSex) return genes;

        uint16 newTrait0 = trait0 ^ 1;
        return (genes & ~uint256(0xFFFF)) | uint256(newTrait0);
    }

    function _pickSex(bytes32 base, uint256 i, uint256 remaining, uint256 remainingFemale)
        internal
        pure
        returns (uint8)
    {
        if (remainingFemale == 0) return uint8(Sex.MALE);
        if (remainingFemale == remaining) return uint8(Sex.FEMALE);

        uint256 r = uint256(keccak256(abi.encode(base, i)));
        return (r % remaining) < remainingFemale ? uint8(Sex.FEMALE) : uint8(Sex.MALE);
    }


    function _batchExactCalldata(address to, uint256[] calldata genesList)
        internal
        returns (uint256 femaleCount)
    {
        uint256 count = genesList.length;
        for (uint256 i = 0; i < count; i++) {
            uint256 g = genesList[i];
            _mintSeedInternal(to, g);
            if (_sexFromGenes(g) == uint8(Sex.FEMALE)) femaleCount++;
        }
    }

    function _batchWithRatioMem(
        address to,
        uint256[] memory genesList,
        uint16 femaleBps,
        bytes32 base
    ) internal returns (uint256 femaleCount) {
        uint256 count = genesList.length;

        uint256 remaining = count;
        uint256 remainingFemale = (count * uint256(femaleBps)) / 10_000;

        for (uint256 i = 0; i < count; i++) {
            uint8 desiredSex = _pickSex(base, i, remaining, remainingFemale);

            uint256 g = _setSexInGenes(genesList[i], desiredSex);
            _mintSeedInternal(to, g);

            if (desiredSex == uint8(Sex.FEMALE)) {
                femaleCount++;
                unchecked { remainingFemale--; }
            }

            unchecked { remaining--; }
        }
    }
}
