// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IStaking {

  struct PeasantPool {
    uint16 poolId;
    uint16 taxRate;         // 0 - 10000 
    uint16 stolenRate;      // 0 - 10000
    uint32 totalStaked;     // amount of peasant token staked (not including level)
    uint32 totalWeight;     // amount of peasant token staked * their levels
    uint32 minTimeToExit;   // days
    uint256 dailyReward;
    uint16[] roleRequired;
  }

  struct RoyalPool {
    uint16 poolId;
    uint16 poolWeight;
    uint32 totalStaked;       // amount of royal token staked (not including level)
    uint32 totalWeight;       // amount of royal token staked * their levels
    uint256 shardPerWeight;
    uint256 unaccountedShards;
    uint16[] roleRequired;
  }

  struct Gen0Pool {
    uint16 taxRate;
    uint32 totalStaked;
    uint256 shardPerWeight;
    uint256 unaccountedShards;
  }

  struct Stake {
    address owner;
    bool isPeasant;
    uint16 poolId;
    uint16 level;
    uint128 stakedAt;
    uint128 lastClaimed;      // last claim date of this stake
    uint256 shardPerWeight; // for royal pool only
    uint256 tokenId;
  }

  function randomRoyalOwner(uint256 seed) external view returns (address);
}