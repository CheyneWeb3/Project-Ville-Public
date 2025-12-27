// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library GeneticsLib {
    uint256 internal constant TRAIT_COUNT = 16;
    uint256 internal constant TRAIT_BITS = 16;
    uint256 internal constant TRAIT_MASK = (1 << TRAIT_BITS) - 1;

    function traitAt(uint256 genes, uint256 idx) internal pure returns (uint16) {
        unchecked {
            uint256 shift = idx * TRAIT_BITS;
            return uint16((genes >> shift) & TRAIT_MASK);
        }
    }

    function setTrait(uint256 genes, uint256 idx, uint16 value) internal pure returns (uint256) {
        unchecked {
            uint256 shift = idx * TRAIT_BITS;
            uint256 cleared = genes & ~(TRAIT_MASK << shift);
            return cleared | (uint256(value) << shift);
        }
    }

    function mix(
        uint256 genesA,
        uint256 genesB,
        uint256 randomness,
        uint16 mutationChanceBps,
        uint16 mutationMaxDelta
    ) internal pure returns (uint256 child) {
        child = 0;
        unchecked {
            for (uint256 i = 0; i < TRAIT_COUNT; i++) {
                uint256 r = uint256(keccak256(abi.encode(randomness, i)));
                bool pickA = (r & 1) == 0;
                uint16 v = pickA ? traitAt(genesA, i) : traitAt(genesB, i);

                uint256 roll = (r >> 1) % 10_000;
                if (roll < mutationChanceBps) {
                    uint16 delta = uint16(((r >> 17) % (uint256(mutationMaxDelta) * 2 + 1)));
                    int256 signedDelta = int256(uint256(delta)) - int256(uint256(mutationMaxDelta));
                    int256 newV = int256(uint256(v)) + signedDelta;
                    if (newV < 0) newV = 0;
                    if (newV > 65535) newV = 65535;
                    v = uint16(uint256(newV));
                }

                child = setTrait(child, i, v);
            }
        }
    }

    function rarityScore(uint256 genes) internal pure returns (uint32 score) {
        unchecked {
            uint256 s = 0;
            for (uint256 i = 0; i < TRAIT_COUNT; i++) s += traitAt(genes, i);
            score = uint32(s);
        }
    }
}
