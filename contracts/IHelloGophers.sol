// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IHelloGophers {

  struct Stat {
    uint16 level;
    uint16 hp;
    uint16 mp;
    uint16 damage;
    uint16 atkSpeed;
    uint16 armor;
    uint16 speed;
  }

  struct Appearance {
    uint16 expression;
    uint16 outfit;
    uint16 weapon;
    uint16 skinColor;
    uint16 background;
  }
  
  struct Trait {
    bool isPeasant;
    uint16 roleId;
    Stat stat;
    Appearance appearance;
  }

  struct Role {
    bool isPeasant;
    string roleName;
    uint16 roleId;
    Stat minStat;
    Stat maxStat;
    Appearance maxAppearance;
    uint256 rarity;
  }

  function getMaxGen0Tokens() external view returns (uint256);
  function getTokenTraits(uint256 tokenId) external view returns (Trait memory);
  function getAppearanceHash(uint256 tokenId) external view returns (uint256);
  function isCustomGopher(uint256 tokenId) external view returns (bool);
}