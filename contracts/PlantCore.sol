// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./GeneticsLib.sol";

interface IERC6551Registry {
    function account(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) external view returns (address);
}

interface IERC6551Account {
    function executeCall(address to, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory);
}

interface IItems1155MintBurn {
    function burn(address account, uint256 id, uint256 value) external;
    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IPlantNFTCore {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function genesOf(uint256 tokenId) external view returns (uint256);

    function mintSeed(address to, uint256 genes) external returns (uint256);

    function mintChild(
        address to,
        uint256 genes,
        uint256 parentA,
        uint256 parentB,
        uint32 generation
    ) external returns (uint256);

    function lineage(uint256 tokenId)
        external
        view
        returns (uint256 genes, uint256 parentA, uint256 parentB, uint32 generation);
}

interface ISeasonalGrowPool {
    function registerHarvest(uint256 seasonId, uint256 tokenId, uint16 qualityBps) external;
}

contract PlantCore is Ownable, ReentrancyGuard {
    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;
    uint256 public immutable accountSalt;

    IPlantNFTCore public immutable plantNFT;
    IItems1155MintBurn public immutable items;

    ISeasonalGrowPool public seasonPool;

    uint256 public activeSeasonId;

    uint256 public constant ITEM_WATER = 1;
    uint256 public constant ITEM_FOOD  = 2;

    uint256 public constant UPGRADE_TIME    = 101;
    uint256 public constant UPGRADE_YIELD   = 102;
    uint256 public constant UPGRADE_QUALITY = 103;

    uint256 public constant FLOWER_BUD = 201;

    uint256 public constant BASE_DURATION = 12 weeks;
    uint256 public constant MIN_DURATION  = 2 weeks;

    enum Stage {
        SEED,
        SPROUT,
        VEGETATION,
        BLOOM,
        HARVEST_WINDOW,
        POST_HARVEST,
        WILTED,
        DEAD
    }

    struct PlantState {
        uint64 plantedAt;
        uint64 lastUpdateAt;

        uint16 water;
        uint16 food;
        uint16 health;
        uint16 quality;

        uint64 pollinatedAt;
        uint32 pollinatedWith;

        bool harvested;
        bool wilted;
        bool dead;

        uint32 timeReductionSec;
        uint16 yieldBoostBps;
        uint16 qualityBoostBps;

        uint16 harvestedQualityBps;
        uint32 harvestSeasonId;

        bool   seedHarvestMode;
        uint16 seedsRemaining;
        uint32 seedFatherId;
        uint32 seedNonce;
        bytes32 seedRandBase;
    }

    mapping(uint256 => PlantState) private _plant;

    uint16 public waterDecayPerDay = 15;
    uint16 public foodDecayPerDay  = 10;

    uint16 public healthPenaltyPerDayWhenDry = 20;
    uint16 public healthPenaltyPerDayWhenHungry = 12;

    uint16 public qualityGainBpsPerDayWhenWell = 120;

    uint16 public dryThreshold = 15;
    uint16 public hungryThreshold = 15;
    uint16 public wiltHealthThreshold = 25;
    uint16 public deadHealthThreshold = 5;

    uint16 public mutationChanceBps = 250;
    uint16 public mutationMaxDelta  = 120;

    uint32 public maxTimeReductionSec = uint32(8 weeks);
    uint16 public maxYieldBoostBps    = 8000;
    uint16 public maxQualityBoostBps  = 8000;

    uint32 public timeReductionPerUpgradeSec = uint32(1 weeks);
    uint16 public yieldBoostPerUpgradeBps    = 500;
    uint16 public qualityBoostPerUpgradeBps  = 500;

    event ActiveSeasonSet(uint256 indexed seasonId);
    event SeasonPoolSet(address indexed pool);

    event Planted(uint256 indexed tokenId, address indexed owner, address indexed tba);

    event Synced(
        uint256 indexed tokenId,
        uint256 at,
        uint16 water,
        uint16 food,
        uint16 health,
        uint16 quality,
        bool wilted,
        bool dead
    );

    event Cared(uint256 indexed tokenId, uint16 waterUsed, uint16 foodUsed);
    event UpgradeApplied(uint256 indexed tokenId, uint256 indexed upgradeId, uint256 qty);

    event Pollinated(uint256 indexed motherId, uint256 indexed fatherId);

    event HarvestRegistered(uint256 indexed tokenId, uint256 indexed seasonId, uint16 qualityBps);
    event FlowerHarvested(uint256 indexed tokenId, uint256 flowersMinted);
    event SeedHarvestScheduled(uint256 indexed motherId, uint256 indexed fatherId, uint16 seedsScheduled);

    event SeedMinted(uint256 indexed motherId, uint256 indexed fatherId, uint256 indexed childId);
    event SeedHarvestFinalized(uint256 indexed motherId);

constructor(
    address _registry,
    address _accountImplementation,
    uint256 _accountSalt,
    address _plantNFT,
    address _items1155,
    address initialOwner
) Ownable(initialOwner) {
    registry = IERC6551Registry(_registry);
    accountImplementation = _accountImplementation;
    accountSalt = _accountSalt;

    plantNFT = IPlantNFTCore(_plantNFT);
    items = IItems1155MintBurn(_items1155);

}

    modifier onlyPlantOwnerOrApproved(uint256 tokenId) {
        address owner = plantNFT.ownerOf(tokenId);
        require(
            msg.sender == owner ||
            msg.sender == plantNFT.getApproved(tokenId) ||
            plantNFT.isApprovedForAll(owner, msg.sender),
            "PlantCore: not owner/approved"
        );
        _;
    }

    /// @notice one-time set deploy other contracts then set season pool addy
    function setSeasonPool(address pool) external onlyOwner {
        require(address(seasonPool) == address(0), "PlantCore: pool already set");
        require(pool != address(0), "PlantCore: pool=0");
        seasonPool = ISeasonalGrowPool(pool);
        emit SeasonPoolSet(pool);
    }

    function setActiveSeason(uint256 seasonId) external onlyOwner {
        activeSeasonId = seasonId;
        emit ActiveSeasonSet(seasonId);
    }

    function tbaOf(uint256 tokenId) public view returns (address) {
        return registry.account(
            accountImplementation,
            block.chainid,
            address(plantNFT),
            tokenId,
            accountSalt
        );
    }

    function getVitals(uint256 tokenId)
        external
        view
        returns (
            uint64 plantedAt,
            uint64 lastUpdateAt,
            uint16 water,
            uint16 food,
            uint16 health,
            uint16 quality,
            bool wilted,
            bool dead,
            bool harvested
        )
    {
        PlantState storage p = _plant[tokenId];
        return (p.plantedAt, p.lastUpdateAt, p.water, p.food, p.health, p.quality, p.wilted, p.dead, p.harvested);
    }

    function getUpgrades(uint256 tokenId)
        external
        view
        returns (uint32 timeReductionSec, uint16 yieldBoostBps, uint16 qualityBoostBps)
    {
        PlantState storage p = _plant[tokenId];
        return (p.timeReductionSec, p.yieldBoostBps, p.qualityBoostBps);
    }

    function getPollination(uint256 tokenId)
        external
        view
        returns (uint64 pollinatedAt, uint32 pollinatedWith)
    {
        PlantState storage p = _plant[tokenId];
        return (p.pollinatedAt, p.pollinatedWith);
    }

    function getHarvestInfo(uint256 tokenId)
        external
        view
        returns (uint16 harvestedQualityBps, uint32 harvestSeasonId)
    {
        PlantState storage p = _plant[tokenId];
        return (p.harvestedQualityBps, p.harvestSeasonId);
    }

    function getSeedSchedule(uint256 tokenId)
        external
        view
        returns (
            bool seedHarvestMode,
            uint16 seedsRemaining,
            uint32 seedFatherId,
            uint32 seedNonce,
            bytes32 seedRandBase
        )
    {
        PlantState storage p = _plant[tokenId];
        return (p.seedHarvestMode, p.seedsRemaining, p.seedFatherId, p.seedNonce, p.seedRandBase);
    }

    function buildApproveItemsOperatorCall(bool approved)
        external
        view
        returns (address target, uint256 value, bytes memory data)
    {
        target = address(items);
        value = 0;
        data = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(this), approved);
    }

    function approveItemsOperatorViaTBA(uint256 tokenId, bool approved)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(tokenId)
    {
        address tba = tbaOf(tokenId);
        bytes memory callData =
            abi.encodeWithSignature("setApprovalForAll(address,bool)", address(this), approved);
        IERC6551Account(tba).executeCall(address(items), 0, callData);
    }

    function _emitSynced(uint256 tokenId, uint256 nowTs) internal {
        PlantState storage p = _plant[tokenId];
        emit Synced(tokenId, nowTs, p.water, p.food, p.health, p.quality, p.wilted, p.dead);
    }

    function mintAndPlant(address to) external nonReentrant returns (uint256 tokenId) {
        require(to != address(0), "PlantCore: to=0");
        uint256 genes = uint256(keccak256(abi.encode(block.prevrandao, block.timestamp, to, address(this))));
        tokenId = plantNFT.mintSeed(to, genes);
        _initPlant(tokenId);
    }

    function initPlant(uint256 tokenId) external nonReentrant onlyPlantOwnerOrApproved(tokenId) {
        require(_plant[tokenId].plantedAt == 0, "PlantCore: already planted");
        _initPlant(tokenId);
    }

    function _initPlant(uint256 tokenId) internal {
        PlantState storage p = _plant[tokenId];
        require(p.plantedAt == 0, "PlantCore: already planted");

        uint64 nowTs = uint64(block.timestamp);
        p.plantedAt = nowTs;
        p.lastUpdateAt = nowTs;

        p.water = 70;
        p.food = 70;
        p.health = 100;
        p.quality = 1000;

        emit Planted(tokenId, plantNFT.ownerOf(tokenId), tbaOf(tokenId));
        _emitSynced(tokenId, block.timestamp);
    }

    function sync(uint256 tokenId) public {
        PlantState storage p = _plant[tokenId];
        require(p.plantedAt != 0, "PlantCore: not planted");
        if (p.dead) return;

        uint256 nowTs = block.timestamp;
        uint256 last = uint256(p.lastUpdateAt);
        if (nowTs <= last) return;

        uint256 elapsed = nowTs - last;
        uint256 daysE18 = (elapsed * 1e18) / 1 days;

        _applyDecay(p, daysE18);
        _applyHealth(p, daysE18);
        _applyQuality(p, daysE18);
        _applyWiltDead(p);

        p.lastUpdateAt = uint64(nowTs);
        _emitSynced(tokenId, nowTs);
    }

    function _applyDecay(PlantState storage p, uint256 daysE18) internal {
        uint256 waterDec = (uint256(waterDecayPerDay) * daysE18) / 1e18;
        uint256 foodDec  = (uint256(foodDecayPerDay)  * daysE18) / 1e18;

        if (waterDec > 0) p.water = uint16((p.water > waterDec) ? (p.water - waterDec) : 0);
        if (foodDec > 0)  p.food  = uint16((p.food  > foodDec)  ? (p.food  - foodDec)  : 0);
    }

    function _applyHealth(PlantState storage p, uint256 daysE18) internal {
        uint256 healthPenalty = 0;

        if (p.water < dryThreshold) {
            healthPenalty += (uint256(healthPenaltyPerDayWhenDry) * daysE18) / 1e18;
        }
        if (p.food < hungryThreshold) {
            healthPenalty += (uint256(healthPenaltyPerDayWhenHungry) * daysE18) / 1e18;
        }

        if (healthPenalty > 0) {
            p.health = uint16((p.health > healthPenalty) ? (p.health - healthPenalty) : 0);
        }
    }

    function _applyQuality(PlantState storage p, uint256 daysE18) internal {
        if (!(p.water >= 60 && p.food >= 60 && p.health >= 70)) return;

        uint256 qGain = (uint256(qualityGainBpsPerDayWhenWell) * daysE18) / 1e18;
        if (qGain == 0) return;

        uint256 boosted = (qGain * (10_000 + uint256(p.qualityBoostBps))) / 10_000;
        uint256 newQ = uint256(p.quality) + boosted;
        if (newQ > 10_000) newQ = 10_000;
        p.quality = uint16(newQ);
    }

    function _applyWiltDead(PlantState storage p) internal {
        if (p.health <= deadHealthThreshold) {
            p.dead = true;
            p.wilted = true;
        } else if (p.health <= wiltHealthThreshold) {
            p.wilted = true;
        } else {
            p.wilted = false;
        }
    }

    function effectiveDuration(uint256 tokenId) public view returns (uint256) {
        PlantState storage p = _plant[tokenId];
        uint256 reduction = uint256(p.timeReductionSec);
        if (reduction > BASE_DURATION) reduction = BASE_DURATION;
        uint256 dur = BASE_DURATION - reduction;
        if (dur < MIN_DURATION) dur = MIN_DURATION;
        return dur;
    }

    function progressBps(uint256 tokenId) public view returns (uint16) {
        PlantState storage p = _plant[tokenId];
        if (p.plantedAt == 0) return 0;
        if (p.harvested) return 10_000;

        uint256 dur = effectiveDuration(tokenId);
        uint256 elapsed = block.timestamp > p.plantedAt ? (block.timestamp - p.plantedAt) : 0;
        if (elapsed >= dur) return 10_000;

        return uint16((elapsed * 10_000) / dur);
    }

    function stageOf(uint256 tokenId) public view returns (Stage) {
        PlantState storage p = _plant[tokenId];
        if (p.plantedAt == 0) return Stage.SEED;
        if (p.dead) return Stage.DEAD;
        if (p.wilted) return Stage.WILTED;
        if (p.harvested) return Stage.POST_HARVEST;

        uint16 prog = progressBps(tokenId);
        if (prog < 1000) return Stage.SEED;
        if (prog < 2500) return Stage.SPROUT;
        if (prog < 5500) return Stage.VEGETATION;
        if (prog < 8000) return Stage.BLOOM;
        return Stage.HARVEST_WINDOW;
    }

    function care(uint256 tokenId, uint16 waterUsed, uint16 foodUsed)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(tokenId)
    {
        PlantState storage p = _plant[tokenId];
        require(p.plantedAt != 0, "PlantCore: not planted");
        require(!p.dead, "PlantCore: dead");

        sync(tokenId);

        address tba = tbaOf(tokenId);

        if (waterUsed > 0) {
            items.burn(tba, ITEM_WATER, waterUsed);
            uint256 newW = uint256(p.water) + uint256(waterUsed);
            if (newW > 100) newW = 100;
            p.water = uint16(newW);
        }

        if (foodUsed > 0) {
            items.burn(tba, ITEM_FOOD, foodUsed);
            uint256 newF = uint256(p.food) + uint256(foodUsed);
            if (newF > 100) newF = 100;
            p.food = uint16(newF);
        }

        if (p.health < 100 && (waterUsed > 0 || foodUsed > 0)) {
            uint256 bump = 3 + (uint256(p.quality) / 2000);
            uint256 newH = uint256(p.health) + bump;
            if (newH > 100) newH = 100;
            p.health = uint16(newH);
            if (p.health > wiltHealthThreshold) p.wilted = false;
        }

        emit Cared(tokenId, waterUsed, foodUsed);
        _emitSynced(tokenId, block.timestamp);
    }

    function applyUpgrade(uint256 tokenId, uint256 upgradeId, uint16 qty)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(tokenId)
    {
        require(qty > 0, "PlantCore: qty=0");
        PlantState storage p = _plant[tokenId];
        require(p.plantedAt != 0, "PlantCore: not planted");
        require(!p.dead, "PlantCore: dead");

        address tba = tbaOf(tokenId);
        items.burn(tba, upgradeId, qty);

        if (upgradeId == UPGRADE_TIME) {
            uint256 addSec = uint256(timeReductionPerUpgradeSec) * uint256(qty);
            uint256 newSec = uint256(p.timeReductionSec) + addSec;
            if (newSec > uint256(maxTimeReductionSec)) newSec = uint256(maxTimeReductionSec);
            p.timeReductionSec = uint32(newSec);
        } else if (upgradeId == UPGRADE_YIELD) {
            uint256 addBps = uint256(yieldBoostPerUpgradeBps) * uint256(qty);
            uint256 newBps = uint256(p.yieldBoostBps) + addBps;
            if (newBps > uint256(maxYieldBoostBps)) newBps = uint256(maxYieldBoostBps);
            p.yieldBoostBps = uint16(newBps);
        } else if (upgradeId == UPGRADE_QUALITY) {
            uint256 addBps = uint256(qualityBoostPerUpgradeBps) * uint256(qty);
            uint256 newBps = uint256(p.qualityBoostBps) + addBps;
            if (newBps > uint256(maxQualityBoostBps)) newBps = uint256(maxQualityBoostBps);
            p.qualityBoostBps = uint16(newBps);
        } else {
            revert("PlantCore: unknown upgrade");
        }

        emit UpgradeApplied(tokenId, upgradeId, qty);
    }

    function pollinate(uint256 motherId, uint256 fatherId) external nonReentrant {
        require(motherId != fatherId, "PlantCore: same plant");

        {
            address om = plantNFT.ownerOf(motherId);
            require(
                msg.sender == om ||
                msg.sender == plantNFT.getApproved(motherId) ||
                plantNFT.isApprovedForAll(om, msg.sender),
                "PlantCore: not approved mother"
            );

            address ofa = plantNFT.ownerOf(fatherId);
            require(
                msg.sender == ofa ||
                msg.sender == plantNFT.getApproved(fatherId) ||
                plantNFT.isApprovedForAll(ofa, msg.sender),
                "PlantCore: not approved father"
            );
        }

        PlantState storage m = _plant[motherId];
        PlantState storage f = _plant[fatherId];
        require(m.plantedAt != 0 && f.plantedAt != 0, "PlantCore: not planted");
        require(!m.dead && !f.dead, "PlantCore: dead");

        sync(motherId);
        sync(fatherId);

        Stage ms = stageOf(motherId);
        Stage fs = stageOf(fatherId);
        require(ms == Stage.BLOOM || ms == Stage.HARVEST_WINDOW, "PlantCore: mother not bloom");
        require(fs == Stage.BLOOM || fs == Stage.HARVEST_WINDOW, "PlantCore: father not bloom");

        m.pollinatedWith = uint32(fatherId);
        m.pollinatedAt = uint64(block.timestamp);

        emit Pollinated(motherId, fatherId);
    }

    function harvest(uint256 tokenId)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(tokenId)
    {
        PlantState storage p = _plant[tokenId];
        require(p.plantedAt != 0, "PlantCore: not planted");
        require(!p.dead, "PlantCore: dead");
        require(!p.harvested, "PlantCore: already harvested");

        sync(tokenId);
        require(progressBps(tokenId) >= 10_000, "PlantCore: not finished");

        _registerHarvest(tokenId);

        if (p.pollinatedWith != 0) {
            _scheduleSeedHarvest(tokenId);
        } else {
            _mintFlowerHarvest(tokenId);
        }

        p.harvested = true;
    }

    function _registerHarvest(uint256 tokenId) internal {
        require(address(seasonPool) != address(0), "PlantCore: seasonPool not set");

        PlantState storage p = _plant[tokenId];

        uint256 seasonId = activeSeasonId;
        require(seasonId != 0, "PlantCore: season not set");

        uint16 q = p.quality;
        if (q > 10_000) q = 10_000;

        p.harvestSeasonId = uint32(seasonId);
        p.harvestedQualityBps = q;

        seasonPool.registerHarvest(seasonId, tokenId, q);
        emit HarvestRegistered(tokenId, seasonId, q);
    }

    function _mintFlowerHarvest(uint256 tokenId) internal {
        PlantState storage p = _plant[tokenId];

        uint256 q = uint256(p.harvestedQualityBps);
        uint256 baseFlowers = 10 + (q * 20) / 10_000;

        uint256 flowers = (baseFlowers * (10_000 + uint256(p.yieldBoostBps))) / 10_000;
        if (flowers > 100) flowers = 100;

        items.mint(tbaOf(tokenId), FLOWER_BUD, flowers, "");
        emit FlowerHarvested(tokenId, flowers);
    }

    function _scheduleSeedHarvest(uint256 motherId) internal {
        PlantState storage p = _plant[motherId];

        uint256 fatherId = uint256(p.pollinatedWith);

        uint256 q = uint256(p.harvestedQualityBps);
        uint256 baseSeeds = 1 + (q / 2500);
        uint256 seeds = (baseSeeds * (10_000 + uint256(p.yieldBoostBps))) / 10_000;
        if (seeds > 10) seeds = 10;

        p.seedHarvestMode = true;
        p.seedsRemaining = uint16(seeds);
        p.seedFatherId = uint32(fatherId);
        p.seedNonce = 0;

        p.seedRandBase = keccak256(
            abi.encode(block.prevrandao, block.timestamp, motherId, fatherId, address(this))
        );

        emit SeedHarvestScheduled(motherId, fatherId, uint16(seeds));
    }

    function _generationOf(uint256 id) internal view returns (uint32 g) {
        (,,, g) = plantNFT.lineage(id);
    }

    function _seedRand(bytes32 base, uint32 nonce) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(base, nonce)));
    }

    function _childGeneration(uint256 motherId, uint256 fatherId) internal view returns (uint32) {
        uint32 genA = _generationOf(motherId);
        uint32 genB = _generationOf(fatherId);
        return (genA >= genB) ? (genA + 1) : (genB + 1);
    }

    function mintNextSeed(uint256 motherId)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(motherId)
        returns (uint256 childId)
    {
        PlantState storage p = _plant[motherId];
        require(p.seedHarvestMode, "PlantCore: not seed harvest");
        require(!p.dead, "PlantCore: dead");
        require(p.seedsRemaining > 0, "PlantCore: no seeds");

        uint256 fatherId = uint256(p.seedFatherId);
        uint32 childGen = _childGeneration(motherId, fatherId);

        uint256 rand = _seedRand(p.seedRandBase, p.seedNonce);

        uint256 mGenes = plantNFT.genesOf(motherId);
        uint256 fGenes = plantNFT.genesOf(fatherId);
        uint256 childGenes = GeneticsLib.mix(mGenes, fGenes, rand, mutationChanceBps, mutationMaxDelta);

        address owner = plantNFT.ownerOf(motherId);
        childId = plantNFT.mintChild(owner, childGenes, motherId, fatherId, childGen);

        _initPlant(childId);

        unchecked {
            p.seedNonce += 1;
            p.seedsRemaining -= 1;
        }

        emit SeedMinted(motherId, fatherId, childId);

        if (p.seedsRemaining == 0) {
            p.seedHarvestMode = false;
            emit SeedHarvestFinalized(motherId);
        }
    }

    function finalizeSeedHarvest(uint256 motherId)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(motherId)
    {
        PlantState storage p = _plant[motherId];
        require(p.seedHarvestMode, "PlantCore: not seed harvest");
        p.seedsRemaining = 0;
        p.seedHarvestMode = false;
        emit SeedHarvestFinalized(motherId);
    }
}
