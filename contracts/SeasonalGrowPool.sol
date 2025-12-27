// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPlantNFTOwnership {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @notice Seasonal survivor pot:
/// - revenue deposits (ERC20) -> 10% to treasury, 90% to seasonPot
/// - only harvested plants registered by PlantCore can claim
/// - claim = baseShare * qualityBps / 10_000
/// - leftover/unclaimed can be swept to treasury (team optionally fund next season manually)
/// - https://www.epochconverter.com to set seasons





contract SeasonalGrowPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    IPlantNFTOwnership public immutable plantNFT;
    address public immutable plantCore;
    address public treasury;

    uint16 public teamCutBps = 1000; /* 1000 basis points = 10% */

    struct Season {
        uint64 startAt;
        uint64 endAt;
        uint64 claimEndAt;
        bool closed;

        uint256 pot;
        uint256 remaining;
        uint256 harvestedCount;
        uint256 baseShare;
    }


    mapping(uint256 => Season) public seasons;


    mapping(uint256 => mapping(uint256 => uint16)) public qualityBpsOf;


    mapping(uint256 => mapping(uint256 => bool)) public claimed;

    event TreasurySet(address indexed treasury);
    event TeamCutBpsSet(uint16 bps);

    event SeasonConfigured(uint256 indexed seasonId, uint64 startAt, uint64 endAt, uint64 claimEndAt);
    event RevenueDeposited(uint256 indexed seasonId, address indexed from, uint256 amount, uint256 teamCut, uint256 toPot);
    event HarvestRegistered(uint256 indexed seasonId, uint256 indexed tokenId, uint16 qualityBps, uint256 harvestedCount);
    event SeasonClosed(uint256 indexed seasonId, uint256 pot, uint256 harvestedCount, uint256 baseShare);
    event Claimed(uint256 indexed seasonId, uint256 indexed tokenId, address indexed to, uint256 amount);
    event Swept(uint256 indexed seasonId, uint256 amount, address indexed to);

    modifier onlyCore() {
        require(msg.sender == plantCore, "SeasonPool: only core");
        _;
    }

    modifier onlyPlantOwnerOrApproved(uint256 tokenId) {
        address owner = plantNFT.ownerOf(tokenId);
        require(
            msg.sender == owner ||
            msg.sender == plantNFT.getApproved(tokenId) ||
            plantNFT.isApprovedForAll(owner, msg.sender),
            "SeasonPool: not owner/approved"
        );
        _;
    }

    constructor(
        address _rewardToken,
        address _plantNFT,
        address _plantCore,
        address _treasury,
        address initialOwner
    ) Ownable(initialOwner) {
        rewardToken = IERC20(_rewardToken);
        plantNFT = IPlantNFTOwnership(_plantNFT);
        plantCore = _plantCore;
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function setTreasury(address t) external onlyOwner {
        require(t != address(0), "SeasonPool: treasury=0");
        treasury = t;
        emit TreasurySet(t);
    }

    function setTeamCutBps(uint16 bps) external onlyOwner {
        require(bps <= 3000, "SeasonPool: too high");
        teamCutBps = bps;
        emit TeamCutBpsSet(bps);
    }

    /// @notice Configure a season window. Can be done ahead of time.
    function configureSeason(uint256 seasonId, uint64 startAt, uint64 endAt, uint64 claimEndAt) external onlyOwner {
        require(startAt < endAt, "SeasonPool: bad window");
        require(endAt < claimEndAt, "SeasonPool: claimEnd");
        Season storage s = seasons[seasonId];
        require(!s.closed, "SeasonPool: closed");
        s.startAt = startAt;
        s.endAt = endAt;
        s.claimEndAt = claimEndAt;
        emit SeasonConfigured(seasonId, startAt, endAt, claimEndAt);
    }

    function isActive(uint256 seasonId) public view returns (bool) {
        Season storage s = seasons[seasonId];
        uint256 t = block.timestamp;
        return (s.startAt != 0 && t >= s.startAt && t < s.endAt && !s.closed);
    }

    /// @notice Deposit revenue into season (ERC20). Auto-splits team cut to treasury.
    function depositRevenue(uint256 seasonId, uint256 amount) external nonReentrant {
        require(amount > 0, "SeasonPool: amount=0");
        Season storage s = seasons[seasonId];
        require(s.startAt != 0, "SeasonPool: unconfigured");
        require(!s.closed, "SeasonPool: closed");

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 teamCut = (amount * teamCutBps) / 10_000;
        uint256 toPot = amount - teamCut;

        if (teamCut > 0) rewardToken.safeTransfer(treasury, teamCut);

        s.pot += toPot;
        s.remaining += toPot;

        emit RevenueDeposited(seasonId, msg.sender, amount, teamCut, toPot);
    }

    /// @notice Called by PlantCore on successful harvest to enroll plant in season and set quality.
    /// Quality is frozen at harvest time.
    function registerHarvest(uint256 seasonId, uint256 tokenId, uint16 qualityBps) external onlyCore {
        Season storage s = seasons[seasonId];
        require(s.startAt != 0, "SeasonPool: unconfigured");
        require(!s.closed, "SeasonPool: closed");
        require(block.timestamp >= s.startAt && block.timestamp < s.endAt, "SeasonPool: not in season");

        require(qualityBps <= 10_000, "SeasonPool: quality");
        require(qualityBpsOf[seasonId][tokenId] == 0, "SeasonPool: already registered"); /* 0 = not registered */

        qualityBpsOf[seasonId][tokenId] = qualityBps;
        s.harvestedCount += 1;

        emit HarvestRegistered(seasonId, tokenId, qualityBps, s.harvestedCount);
    }

    /// @notice Close season: compute baseShare = pot / harvestedCount.
    /// After close, claims open until claimEndAt.
    function closeSeason(uint256 seasonId) external onlyOwner {
        Season storage s = seasons[seasonId];
        require(!s.closed, "SeasonPool: already closed");
        require(s.startAt != 0, "SeasonPool: unconfigured");
        require(block.timestamp >= s.endAt, "SeasonPool: too early");

        s.closed = true;

        if (s.harvestedCount > 0) {
            s.baseShare = s.pot / s.harvestedCount;
        } else {
            s.baseShare = 0;
        }

        emit SeasonClosed(seasonId, s.pot, s.harvestedCount, s.baseShare);
    }

    function pending(uint256 seasonId, uint256 tokenId) public view returns (uint256) {
        Season storage s = seasons[seasonId];
        if (!s.closed) return 0;
        if (claimed[seasonId][tokenId]) return 0;

        uint16 q = qualityBpsOf[seasonId][tokenId];
        if (q == 0) return 0; // not registered/harvested

        // payout = baseShare * qualityBps / 10_000
        return (s.baseShare * uint256(q)) / 10_000;
    }

    function claim(uint256 seasonId, uint256 tokenId, address to)
        external
        nonReentrant
        onlyPlantOwnerOrApproved(tokenId)
        returns (uint256 amount)
    {
        require(to != address(0), "SeasonPool: to=0");
        Season storage s = seasons[seasonId];
        require(s.closed, "SeasonPool: not closed");
        require(block.timestamp <= s.claimEndAt, "SeasonPool: claim over");
        require(!claimed[seasonId][tokenId], "SeasonPool: claimed");

        amount = pending(seasonId, tokenId);
        require(amount > 0, "SeasonPool: nothing");

        claimed[seasonId][tokenId] = true;

        // If many plants claim, ensure remaining never underflows.
        require(s.remaining >= amount, "SeasonPool: insufficient remaining");
        s.remaining -= amount;

        rewardToken.safeTransfer(to, amount);

        emit Claimed(seasonId, tokenId, to, amount);
    }

    /// @notice After claim window ends, sweep leftover/unclaimed to treasury.
    function sweepLeftoverToTreasury(uint256 seasonId) external nonReentrant onlyOwner returns (uint256 swept) {
        Season storage s = seasons[seasonId];
        require(s.closed, "SeasonPool: not closed");
        require(block.timestamp > s.claimEndAt, "SeasonPool: too early");

        swept = s.remaining;
        if (swept == 0) return 0;

        s.remaining = 0;
        rewardToken.safeTransfer(treasury, swept);

        emit Swept(seasonId, swept, treasury);
    }
}
