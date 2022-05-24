// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./HelloGophers.sol";
import "./Shard.sol";
import "./IStaking.sol";
import "./RandomBase.sol";

contract Staking is 
  IStaking, 
  RandomBase,
  Initializable,
  IERC721ReceiverUpgradeable, 
  OwnableUpgradeable, 
  PausableUpgradeable,
  ReentrancyGuardUpgradeable 
{
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  /** CONSTANT VARIABLES */

  // total number of shards rewards allocated for farming 34 billion
  uint16 public constant MAX_RATE = 10000; 
  uint256 public constant MAXIMUM_GLOBAL_SHARD = 34000000000 ether; 

  /** STATE VARIABLES */

  HelloGophers public helloGophers;  // reference to the HelloGophers ERC721 contract
  Shard public shard;                // reference to the Shard ERC20 contract
  
  uint256 public startTime;
  uint256 public unlockAllTime;
  uint256[49] public lockRewardPercents;             // 0-10000
  uint256[49] public lockRewardDates;        

  uint256 public totalShardPeasantEarned;
  uint256 public totalShardRoyalEarned;
  uint256 public totalGen1TaxPaid;

  uint256 public totalRoyalWeightStaked;  // poolWeight * amount of royal staked in the pool  
  uint256 public totalRoyalCharacters;

  uint16 stolenRateDeductionPerLevel;
  uint16 taxRateDeductionPerLevel;

  PeasantPool[] public peasantPools;  
  RoyalPool[] public royalPools;      
  Gen0Pool public gen0Pool;

  mapping(uint256 => Stake) public stakes;                // map tokenId to Stake
  mapping(uint256 => Stake) public gen0Stakes;            // map tokenId to gen 0 Stake
  mapping(uint256 => Stake[]) public royalStakes;         // map royalPoolId to Stake Array. Track Stake in each royalPool
  mapping(uint256 => uint256) public royalStakeIndexes;   // map tokenId to array position in royalStakes
  mapping(address => uint256) public lockedRewards;       // amount of rewards locked for an address

  mapping(address => EnumerableSetUpgradeable.UintSet) private _stakedTokens;

  /** EVENTS */
  
  event TokenStaked(address indexed owner, uint256 indexed tokenId, uint256 indexed poolId, bool isPeasant);
  event PeasantClaimed(address indexed owner, uint256 indexed tokenId, uint256 rewards, bool indexed isUnstaked);
  event RoyalClaimed(address indexed owner, uint256 indexed tokenId, uint256 rewards, bool indexed isUnstaked);
  event LockedRewardsClaimed(address indexed owner, uint256 rewards);

  /** INITIALIZER */

  function initialize(address _helloGophers, address _shard, uint256 _startTime) public initializer {
    __Ownable_init();
    __Pausable_init();

    helloGophers = HelloGophers(_helloGophers);
    shard = Shard(_shard);
    startTime = _startTime;
    unlockAllTime = startTime + 49 weeks;

    for (uint256 i = 0; i < 49; i++) {
      lockRewardPercents[i] = MAX_RATE - ((i+1) * 200);
      lockRewardDates[i] = startTime + ((i+1) * 1 weeks);
    }

    gen0Pool = Gen0Pool(500, 0, 0, 0);

    stolenRateDeductionPerLevel = 100;
    taxRateDeductionPerLevel = 100;
  }

  /** STAKE */

  function stakeManyRoyalAndPeasant(uint256[] calldata tokenIds, uint16[] calldata poolIds) external nonReentrant {
    require(tx.origin == _msgSender(), "EOA only");
    require(block.timestamp >= startTime, "Staking not started yet");
    require(tokenIds.length == poolIds.length, "tokenIds and poolIds length not match");

    for (uint256 i = 0; i < tokenIds.length; i++) {
      require(helloGophers.ownerOf(tokenIds[i]) == _msgSender(), "NOT YOUR TOKEN");

      helloGophers.transferFrom(_msgSender(), address(this), tokenIds[i]);
      if (isPeasant(tokenIds[i])){
        _addPeasentToPool(_msgSender(), tokenIds[i], poolIds[i]);
      } else {
        _addRoyalToPool(_msgSender(), tokenIds[i], poolIds[i]);
      }
    }
  }

  function _addPeasentToPool(address account, uint256 tokenId, uint16 poolId) internal whenNotPaused {
    // check for pool requirements
    (, uint16 roleId, HelloGophers.Stat memory stat,) = helloGophers.tokenTraits(tokenId);
    PeasantPool storage peasantPool = peasantPools[poolId];
    require(peasantPool.dailyReward > 0, "peasantPool does not exists"); 
    bool isRoleMatch = false;
    for (uint256 i = 0; i < peasantPool.roleRequired.length; i++) {
      if (peasantPool.roleRequired[i] == roleId) {
        isRoleMatch = true;
        break;
      } 
    }
    require(isRoleMatch, "role does not meet requirement");

    Stake memory _stake = Stake({
      owner: account,
      isPeasant: true,
      poolId: poolId,
      level: stat.level,
      stakedAt: uint128(block.timestamp),
      lastClaimed: uint128(block.timestamp),
      shardPerWeight: 0,
      tokenId: tokenId
    });
    stakes[tokenId] = _stake;

    peasantPools[poolId].totalStaked += 1;
    peasantPools[poolId].totalWeight += stat.level;

    if(tokenId < helloGophers.getMaxGen0Tokens()) {
      _addTokenToGen0Pool(_stake);
    }

    EnumerableSetUpgradeable.add(_stakedTokens[_msgSender()], tokenId);

    emit TokenStaked(account, tokenId, poolId, true);
  }

  function _addRoyalToPool(address account, uint256 tokenId, uint16 poolId) internal whenNotPaused {
    // check for pool requirements
    (, uint16 roleId, HelloGophers.Stat memory stat,) = helloGophers.tokenTraits(tokenId);
    RoyalPool storage royalPool = royalPools[poolId];
    require(royalPool.poolWeight > 0, "royalPool does not exists"); 
    bool isRoleMatch = false;
    for (uint256 i = 0; i < royalPool.roleRequired.length; i++) {
      if (royalPool.roleRequired[i] == roleId)  {
        isRoleMatch = true;
        break;
      }
    }
    require(isRoleMatch, "role does not meet requirement");

    Stake memory _stake = Stake({
      owner: account,
      isPeasant: false,
      poolId: poolId,
      level: stat.level,
      stakedAt: uint128(block.timestamp),
      lastClaimed: uint128(block.timestamp),
      shardPerWeight: royalPool.shardPerWeight,
      tokenId: tokenId
    });
    stakes[tokenId] = _stake;

    royalStakeIndexes[tokenId] = royalStakes[royalPool.poolId].length;
    royalStakes[royalPool.poolId].push(_stake);

    royalPools[poolId].totalStaked += 1;
    royalPools[poolId].totalWeight += stat.level;
    totalRoyalWeightStaked += royalPool.poolWeight;

    if(tokenId < helloGophers.getMaxGen0Tokens()) {
      _addTokenToGen0Pool(_stake);
    }

    EnumerableSetUpgradeable.add(_stakedTokens[_msgSender()], tokenId);

    emit TokenStaked(account, tokenId, poolId, false);
  }

  function _addTokenToGen0Pool(Stake memory stake) internal whenNotPaused {
    require(stake.tokenId < helloGophers.getMaxGen0Tokens(), "Not gen 0 token");

    Stake memory gen0Stake = stake;

    gen0Stake.poolId = 0;
    gen0Stake.shardPerWeight = gen0Pool.shardPerWeight;
    gen0Stakes[stake.tokenId] = gen0Stake;

    gen0Pool.totalStaked += 1;
  }

  /** CLAIMING / UNSTAKING */

  function claimManyRoyalAndPeasant(uint256[] calldata tokenIds, bool shouldUnstake) external whenNotPaused nonReentrant {
    require(tx.origin == _msgSender(), "EOA only");

    uint256 rewards = 0;
    uint256 totalReleasedRewards = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (isPeasant(tokenIds[i])){
        rewards = _claimPeasentFromPool(tokenIds[i], shouldUnstake);
      } else {
        rewards = _claimRoyalFromPool(tokenIds[i], shouldUnstake);
      }

      totalReleasedRewards += rewards;
      if (rewards > 0 && block.timestamp < unlockAllTime) {
        uint256 lockPercentage = getLockPercentage(block.timestamp);
        uint256 lockRewards = rewards * lockPercentage / MAX_RATE;

        lockedRewards[_msgSender()] += lockRewards;
        totalReleasedRewards -= lockRewards;
      }
    }

    if (totalReleasedRewards == 0) return;
    shard.mint(_msgSender(), totalReleasedRewards);
  }

  function _claimPeasentFromPool(uint256 tokenId, bool shouldUnstake) internal returns (uint256 rewards) {
    Stake memory stake = stakes[tokenId];
    require(stake.owner == _msgSender(), "NOT YOUR TOKEN");
    PeasantPool storage peasantPool = peasantPools[stake.poolId];

    require(!(shouldUnstake && block.timestamp - stake.stakedAt < peasantPool.minTimeToExit), "Cannot unstake before minimum time to exit");

    rewards = pendingPeasantRewards(stake, peasantPool);

    if (shouldUnstake) {
      if (random() % MAX_RATE <= (peasantPool.stolenRate - (stake.level - 1) * stolenRateDeductionPerLevel)) {   // each level decrease 1% chance 
        _payRoyalTax(rewards);
        totalShardRoyalEarned += rewards;
        rewards = 0;
      }
      peasantPools[stake.poolId].totalStaked -= 1;
      peasantPools[stake.poolId].totalWeight -= stake.level;
      delete stakes[tokenId];
      EnumerableSetUpgradeable.remove(_stakedTokens[_msgSender()], tokenId);

      totalShardPeasantEarned += rewards;
      helloGophers.safeTransferFrom(address(this), _msgSender(), tokenId, "");
    } else {
      uint256 taxAmount = rewards * (peasantPool.taxRate - (stake.level - 1) * taxRateDeductionPerLevel) / MAX_RATE;    // each level decrease 1% tax 
      _payRoyalTax(taxAmount);
      rewards -= taxAmount;
      stakes[tokenId].lastClaimed = uint128(block.timestamp);
      totalShardPeasantEarned += rewards;
      totalShardRoyalEarned += taxAmount;
    }

    rewards = _handleGen1Tax(tokenId, rewards, shouldUnstake);

    emit PeasantClaimed(_msgSender(), tokenId, rewards, shouldUnstake);
  }

  function _claimRoyalFromPool(uint256 tokenId, bool shouldUnstake) internal returns (uint256 rewards) {
    Stake memory stake = stakes[tokenId];
    require(stake.owner == _msgSender(), "NOT YOUR TOKEN");
    RoyalPool storage royalPool = royalPools[stake.poolId];

    rewards = pendingRoyalRewards(stake, royalPool);

    if (shouldUnstake) {
      royalPools[stake.poolId].totalStaked -= 1;
      royalPools[stake.poolId].totalWeight -= stake.level;
      totalRoyalWeightStaked -= royalPool.poolWeight;

      Stake memory lastStake = royalStakes[stake.poolId][royalStakes[stake.poolId].length - 1];
      royalStakes[stake.poolId][royalStakeIndexes[tokenId]] = lastStake;                // change royalStakes of removed stake to lastStake (in the same pool)
      royalStakeIndexes[lastStake.tokenId] = royalStakeIndexes[tokenId];                // change royalStakeIndexes of lastStake to royalStakeIndexes of removed tokenId
      royalStakes[stake.poolId].pop();                                                  // remove lastStake in royalStakes
      delete royalStakeIndexes[tokenId];
      delete stakes[tokenId];
      EnumerableSetUpgradeable.remove(_stakedTokens[_msgSender()], tokenId);

      helloGophers.safeTransferFrom(address(this), _msgSender(), tokenId, "");
    } else {
      stakes[tokenId].shardPerWeight = royalPool.shardPerWeight;
    }

    rewards = _handleGen1Tax(tokenId, rewards, shouldUnstake);

    emit RoyalClaimed(_msgSender(), tokenId, rewards, shouldUnstake);
  }

  function _claimGen0FromPool(uint256 tokenId, uint256 rewards, bool shouldUnstake) internal returns (uint256) {
    Stake memory stake =  gen0Stakes[tokenId];
    uint256 gen0Rewards = gen0Pool.shardPerWeight - stake.shardPerWeight;
    rewards += gen0Rewards;
    gen0Stakes[tokenId].shardPerWeight = gen0Pool.shardPerWeight;

    if(shouldUnstake) {
      gen0Pool.totalStaked -= 1;
      delete gen0Stakes[tokenId];
    }

    return rewards;
  }

  /** CLAIM LOCKED REWARDS */

  function claimLockedRewards() external {
    require(block.timestamp >= unlockAllTime, "Rewards are not unlocked yet");
    uint256 unlockedAmount = lockedRewards[_msgSender()];
    lockedRewards[_msgSender()] = 0;
    shard.mint(_msgSender(), unlockedAmount);

    emit LockedRewardsClaimed(_msgSender(), unlockedAmount);
  }

  /** UTILS */

  function _payRoyalTax(uint256 rewards) internal {
    for (uint256 i = 0; i < royalPools.length; i++) {
      RoyalPool storage royalPool = royalPools[i];
      uint256 poolRewards = rewards * royalPool.roleRequired.length / totalRoyalCharacters;
      if (royalPool.totalWeight == 0) {
        royalPool.unaccountedShards += poolRewards;
        continue;
      }
      royalPool.shardPerWeight += (poolRewards + royalPool.unaccountedShards) / uint256(royalPool.totalWeight);
      royalPool.unaccountedShards = 0;
    }
  }

  function _payGen0Tax(uint256 rewards) internal {
    if (gen0Pool.totalStaked == 0) {
      gen0Pool.unaccountedShards += rewards;
      return;
    }
    gen0Pool.shardPerWeight += (rewards + gen0Pool.unaccountedShards) / uint256(gen0Pool.totalStaked);
    gen0Pool.unaccountedShards = 0;
  }

  function _handleGen1Tax(uint256 tokenId, uint256 rewards, bool shouldUnstake) internal returns (uint256) {
    if(tokenId < helloGophers.getMaxGen0Tokens()) {
      // get taxed reward from gen 1
      rewards = _claimGen0FromPool(tokenId, rewards, shouldUnstake);
    } else {
      // pay tax reward to gen 0
      uint256 taxAmount = rewards * gen0Pool.taxRate / MAX_RATE;
      _payGen0Tax(taxAmount);
      rewards -= taxAmount;
      totalGen1TaxPaid += taxAmount;
    }

    return rewards;
  }

  /** READ */

  function getPeasantPoolAtIndex(uint256 index) external view returns (PeasantPool memory) {
    return peasantPools[index];
  }

  function getRoyalPoolAtIndex(uint256 index) external view returns (RoyalPool memory) {
    return royalPools[index];
  }

  function isPeasant(uint256 tokenId) public view returns (bool peasant) {
    (peasant,,,) = helloGophers.tokenTraits(tokenId);
  }

  function getLockPercentage(uint256 timestamp) public view returns (uint256) {
    if (timestamp < startTime) return 0;

    for (uint256 i = 0; i < lockRewardDates.length; i++) {
      uint256 endDate = lockRewardDates[i];
      if (timestamp <= endDate) {
        return lockRewardPercents[i];
      }
    }

    return 0;
  }

  function pendingPeasantRewards(Stake memory stake, PeasantPool memory peasantPool) public view returns (uint256 rewards) {
    if (totalShardPeasantEarned + totalShardRoyalEarned < MAXIMUM_GLOBAL_SHARD) {
      rewards = (block.timestamp - stake.lastClaimed) * stake.level * peasantPool.dailyReward / 1 days;
    } else {
      rewards = 0;
    }

    if(totalShardPeasantEarned + totalShardRoyalEarned + rewards > MAXIMUM_GLOBAL_SHARD) {
      rewards = MAXIMUM_GLOBAL_SHARD - totalShardPeasantEarned - totalShardRoyalEarned;
    }

    return rewards;
  }

  function pendingRoyalRewards(Stake memory stake, RoyalPool memory royalPool) public pure returns (uint256 rewards) {
    return rewards =  stake.level * (royalPool.shardPerWeight - stake.shardPerWeight);
  }

  /** READ ONLY */

  function randomRoyalOwner(uint256 seed) external override view returns (address) {
    if (totalRoyalWeightStaked == 0) return address(0x0);
    uint256 rand = seed % totalRoyalWeightStaked; 

    uint256 cumulative;
    seed >>= 32;
    for (uint256 i = 0; i < royalPools.length; i++) {
      cumulative += royalPools[i].totalStaked * royalPools[i].poolWeight;
      
      if (rand >= cumulative) continue;

      return royalStakes[i][seed % royalStakes[i].length].owner;
    }
    return address(0x0);
  }

  function getStakedTokenIds(address account) public view returns (uint256[] memory) {
    return EnumerableSetUpgradeable.values(_stakedTokens[account]);
  }

  function getStakedTokensInfo(address account) external view returns (Stake[] memory) {
    uint256[] memory tokenIds = getStakedTokenIds(account);
    Stake[] memory _stakes = new Stake[](tokenIds.length);

    for(uint256 i = 0; i < tokenIds.length; i++) {
      _stakes[i] = stakes[tokenIds[i]];
    }

    return _stakes;
  }

  function onERC721Received(
    address,
    address from,
    uint256,
    bytes calldata
  ) external pure override returns (bytes4) {
    require(from == address(0x0), "Cannot send tokens to Staking directly");
    return IERC721ReceiverUpgradeable.onERC721Received.selector;
  }

  /** ADMIN */

  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }

  function setStolenRateDeductionPerLevel(uint16 _stolenRateDeductionPerLevel) external onlyOwner {
    require(_stolenRateDeductionPerLevel <= MAX_RATE, "Too high");
    stolenRateDeductionPerLevel = _stolenRateDeductionPerLevel;
  }

  function setTaxRateDeductionPerLevel(uint16 _taxRateDeductionPerLevel) external onlyOwner {
    require(_taxRateDeductionPerLevel <= MAX_RATE, "Too high");
    taxRateDeductionPerLevel = _taxRateDeductionPerLevel;
  }

  function setGen0PoolTaxRate(uint16 _taxRate) external onlyOwner {
    require(_taxRate <= MAX_RATE, "Too high");
    gen0Pool.taxRate = _taxRate;
  }

  function addPeasentPools(PeasantPool[] memory _peasantPools) external onlyOwner {
    uint16 _poolId = uint16(peasantPools.length);
    for (uint256 i = 0; i < _peasantPools.length; i++) {
      PeasantPool memory _peasantPool = _peasantPools[i];

      _peasantPool.poolId = _poolId;
      peasantPools.push(_peasantPool);
      _poolId++;
    }
  }

  function addRoyalPools(RoyalPool[] memory _royalPools) external onlyOwner {
    uint16 _poolId = uint16(royalPools.length); 
    for (uint256 i = 0; i < _royalPools.length; i++) {
      RoyalPool memory _royalPool = _royalPools[i];

      _royalPool.poolId = _poolId;
      royalPools.push(_royalPool);

      // role required cannot include role id that is already included in another pool
      // else the reward calculation will be incorrect
      totalRoyalCharacters += _royalPool.roleRequired.length;
      _poolId++;
    }
  }
}
