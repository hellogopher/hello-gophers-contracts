// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./ERC721EnumerableUpgradeable.sol";
import "./IStaking.sol";
import "./ITraits.sol";
import "./IHelloGophers.sol";
import "./RandomBase.sol";

contract HelloGophers is
  IHelloGophers,
  RandomBase,
  Initializable,
  ERC721EnumerableUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable
{
  /** CONSTANT VARIABLES */

  uint256 public constant MAX_GEN0_TOKENS = 10000;
  uint256 public constant MAX_GIVEAWAY_TOKENS = 2000;

  /** STATE VARIABLES */

  address public staking;
  address public traits;
  address public shard;
  address public usdc;

  uint256 public minted;
  uint256 public giveawayMinted;

  uint256 public mintCost;
  uint256 public usdcMintCost;
  uint256 public maxPerMint;

  uint256 public costPerLevel;
  uint16 public maxLevel;

  uint16[] public peasantRarityIndexes;
  uint256[] public peasantRarities;
  uint16[] public royalRarityIndexes;
  uint256[] public royalRarities;

  mapping(uint256 => Trait) public tokenTraits;   // map tokenId to a struct containing the token's traits
  mapping(uint256 => Role) public roles;          // map roleId to a struct containing the role's info

  mapping(address => bool) public isWhitelisted;
  mapping(address => uint256) public whitelistMintCount;

  mapping(uint256 => bool) public isCustomGopher;
  mapping(uint256 => uint256) public tokenIdToAppearanceHashes;

  /** EVENTS */

  event TokenStolen(address indexed owner, address indexed thief, uint256 indexed tokenId);

  /** INITIALIZER */

  function initialize(address _traits, address _shard, address _usdc) public initializer {
    __Ownable_init();
    __Pausable_init();
    __ERC721Enumerable_init("Hello Gophers", "HG");

    traits = _traits;
    shard = _shard;
    usdc = _usdc;

    mintCost = 125000 ether;
    usdcMintCost = 125000000;
    costPerLevel =  130000 ether;
    maxPerMint = 10;
    maxLevel = 10;
  }

  /** MINT FUNCTION */

  function mintGophers(uint256 amount) external whenNotPaused {
    require(tx.origin == _msgSender(), "Only EOA");
    require(amount > 0 && amount <= maxPerMint, "Invalid mint amount");

    if (minted < MAX_GEN0_TOKENS) {
      require(minted + amount <= MAX_GEN0_TOKENS, "All tokens on-sale already sold");
      uint256 _mintCost = amount * usdcMintCost;
      IERC20Upgradeable(usdc).transferFrom(_msgSender(), owner(), _mintCost);
    } else {
      uint256 _mintCost = amount * mintCost;
      IERC20Upgradeable(shard).transferFrom(_msgSender(), owner(), _mintCost);
    }

    for (uint256 i = 0; i < amount; i++) {
      _mint();
    }
  }

  function mintGiveawayGophers(uint256 amount) external whenNotPaused {
    require(tx.origin == _msgSender(), "Only EOA");
    require(isWhitelisted[_msgSender()], "Not whitelisted");
    require(amount > 0 && amount <= whitelistMintCount[_msgSender()], "Invalid mint amount");
    require(giveawayMinted + amount <= MAX_GIVEAWAY_TOKENS, "All giveaway tokens minted");

    for (uint256 i = 0; i < amount; i++) {
      _mint();
      giveawayMinted++;
    }

    whitelistMintCount[_msgSender()] -= amount;
  }

  function mintCustomGopher(address recipient, Trait memory _trait) external whenNotPaused onlyOwner {
    isCustomGopher[minted] = true;
    tokenTraits[minted] = _trait;

    _safeMint(recipient, minted);
    minted++;
  }

  function _mint() internal {
    uint256 seed = random();
    tokenTraits[minted]  = _generateTrait(seed);
    uint256 appearanceHash = hashRoleAndAppearance(tokenTraits[minted]);
    tokenIdToAppearanceHashes[minted] = appearanceHash;

    // Select recipient 
    address recipient = _selectRecipient(seed);
    _safeMint(recipient, minted);

    if(recipient != _msgSender()) {
      emit TokenStolen(_msgSender(), recipient, minted);
    }

    minted++;
  }

  /** LEVEL FUNCTION */

  function levelUpGopher(uint256 tokenId, uint16 level) external whenNotPaused {
    require(tokenId <= minted, "Token id does not exists");
    require(ownerOf(tokenId) == _msgSender(), "NOT YOUR TOKEN");
    require(tokenTraits[tokenId].stat.level + level <= maxLevel, "Exceed max level");

    uint256 levelUpCost = level * costPerLevel;
    IERC20Upgradeable(shard).transferFrom(_msgSender(), owner(), levelUpCost);
    tokenTraits[tokenId].stat.level += level;
  }

  /** READ */

  function getMaxGen0Tokens() external view override returns (uint256) {
    return MAX_GEN0_TOKENS;
  }

  function getTokenTraits(uint256 tokenId) external view override returns (Trait memory) {
    return tokenTraits[tokenId];
  }

  function getAppearanceHash(uint256 tokenId) external view override returns (uint256) {
    return tokenIdToAppearanceHashes[tokenId];
  }

  function tokensOfOwner(address owner) external view returns (uint256[] memory) {
    return tokensOfOwner(owner, 0, balanceOf(owner));
  }

  // to handle out of gas situation if an account own too much tokens
  function tokensOfOwner(address owner, uint256 skip, uint256 limit) public view returns (uint256[] memory) {
    // length will be 0 if skip > balanceOf(owner)
    uint256 length = limit > balanceOf(owner) - skip ? balanceOf(owner) - skip : limit;
    uint256 end = skip + limit > balanceOf(owner) ? balanceOf(owner) : skip + limit;

    uint256[] memory tokenIds = new uint256[](length);
    uint256 idx = 0;
    for(uint256 i = skip; i < end; i++) {
      tokenIds[idx] = tokenOfOwnerByIndex(owner, i);
      idx++;
    }

    return tokenIds;
  }

  /** ADMIN */

  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }

  function setStaking(address _staking) external onlyOwner {
    staking = _staking;
  }

  function setTraits(address _traits) external onlyOwner {
    traits = _traits;
  }

  function setMintCost(uint256 _mintCost) external onlyOwner {
    mintCost = _mintCost;
  }

  function setUsdcMintCost(uint256 _usdcMintCost) external onlyOwner {
    usdcMintCost = _usdcMintCost;
  }

  function setCostPerLevel(uint256 _costPerLevel) external onlyOwner {
    costPerLevel = _costPerLevel;
  }

  function setMaxPerMint(uint256 _maxPerMint) external onlyOwner {
    maxPerMint = _maxPerMint;
  }

  function setMaxLevel(uint16 _maxLevel) external onlyOwner {
    maxLevel = _maxLevel;
  }

  function addRoles(Role[] memory _roles) external onlyOwner {
    uint16 roleId;
    uint256 rarity;

    for (uint256 i = 0; i < _roles.length; i++) {
      roleId = _roles[i].roleId;
      require(roles[roleId].rarity == 0, "Cannot add to existing role");
      roles[roleId] = _roles[i];
      if (_roles[i].isPeasant) {
        peasantRarityIndexes.push(roleId);
        rarity = peasantRarities.length == 0 ? _roles[i].rarity : peasantRarities[peasantRarities.length - 1] + _roles[i].rarity;
        peasantRarities.push(rarity);
      } else {
        royalRarityIndexes.push(roleId);
        rarity = royalRarities.length == 0 ? _roles[i].rarity : royalRarities[royalRarities.length - 1] + _roles[i].rarity;
        royalRarities.push(rarity); 
      }
    }
  }

  function editRoleMaxAppearances(uint16[] calldata _roleIds, Appearance[] calldata _appearances) external onlyOwner {
    require(_roleIds.length == _appearances.length, "Mismatched inputs");
    for(uint256 i = 0; i < _appearances.length; i++) {
      roles[_roleIds[i]].maxAppearance = _appearances[i];
    }
  }

  function setWhitelist(address _user, uint256 _mintCount, bool _isWhitelist) public onlyOwner {
    if(_isWhitelist) {
      isWhitelisted[_user] = true;
      whitelistMintCount[_user] = _mintCount;
    } else {
      isWhitelisted[_user] = false;
      whitelistMintCount[_user] = 0;
    }
  }

  function setWhitelistBulk(address[] memory _users, uint256[] memory _mintCounts, bool[] memory _isWhitelists) external onlyOwner {
    require(_users.length == _mintCounts.length, "Invalid length");
    require(_users.length == _isWhitelists.length, "Invalid length");
    
    for(uint256 i = 0; i < _users.length; i++){
      setWhitelist(_users[i], _mintCounts[i], _isWhitelists[i]);
    }
  }

  /** UTILS */

  function hashRoleAndAppearance(Trait memory _trait) internal pure returns (uint256) {
    return
      uint256(
        bytes32(
          abi.encodePacked(
            _trait.roleId,
            _trait.appearance.expression,
            _trait.appearance.outfit,
            _trait.appearance.weapon,
            _trait.appearance.skinColor,
            _trait.appearance.background
          )
        )
      );
  }

  function _generateTrait(uint256 seed) internal view returns (Trait memory _trait) {
    // generate gopher type
    bool isPeasant =  (seed & 0xFFFF) % 10 != 0;
    _trait.isPeasant = isPeasant;

    // generate role id
    seed >>= 16;
    uint16 roleId = _selectRole(uint16(seed & 0xFFFF), isPeasant);
    _trait.roleId = roleId;

    // set level to 1
    _trait.stat.level = uint16(1);

    // generate stats
    seed >>= 16;
    _trait.stat.hp = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.hp, roles[roleId].maxStat.hp);
    seed >>= 16;
    _trait.stat.mp = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.mp, roles[roleId].maxStat.mp);
    seed >>= 16; 
    _trait.stat.damage = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.damage, roles[roleId].maxStat.damage);
    seed >>= 16; 
    _trait.stat.atkSpeed = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.atkSpeed, roles[roleId].maxStat.atkSpeed);
    seed >>= 16; 
    _trait.stat.armor = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.armor, roles[roleId].maxStat.armor);
    seed >>= 16; 
    _trait.stat.speed = _selectRandomUintFromRange(uint16(seed & 0xFFFF), roles[roleId].minStat.speed, roles[roleId].maxStat.speed);

    // generate appearances
    seed >>= 16;
    _trait.appearance.expression = _selectRandomUintFromRange(uint16(seed & 0xFFFF), 0, roles[roleId].maxAppearance.expression - 1);
    seed >>= 16;
    _trait.appearance.outfit = _selectRandomUintFromRange(uint16(seed & 0xFFFF), 0, roles[roleId].maxAppearance.outfit - 1);
    seed >>= 16;
    _trait.appearance.weapon = _selectRandomUintFromRange(uint16(seed & 0xFFFF), 0, roles[roleId].maxAppearance.weapon - 1);
    seed >>= 16;
    _trait.appearance.skinColor = _selectRandomUintFromRange(uint16(seed & 0xFFFF), 0, roles[roleId].maxAppearance.skinColor - 1);
    seed >>= 16;
    _trait.appearance.background = _selectRandomUintFromRange(uint16(seed & 0xFFFF), 0, roles[roleId].maxAppearance.background - 1);
  }

  function _selectRole(uint16 seed, bool isPeasant) internal view returns (uint16) {
    uint256 rand;
    if (isPeasant) {
      rand = uint256(seed) % peasantRarities[peasantRarities.length - 1];
      for (uint256 i = 0; i < peasantRarities.length; i++) {
        if (rand < peasantRarities[i]) {
          return peasantRarityIndexes[i];
        }
      }
      return peasantRarityIndexes[rand % peasantRarityIndexes.length];
    } else {
      rand = uint256(seed) % royalRarities[royalRarities.length - 1];
      for (uint256 i = 0; i < royalRarities.length; i++) {
        if (rand < royalRarities[i]) {
          return royalRarityIndexes[i];
        }
      }
      return royalRarityIndexes[rand % royalRarityIndexes.length];
    }
  }

  function _selectRandomUintFromRange(uint16 seed, uint16 min, uint16 max) internal pure returns (uint16) {
    return seed % (max - min + 1) + min; // The maximum is inclusive and the minimum is inclusive
  }

  function _selectRecipient(uint256 seed) internal view returns (address) {
    if ((seed >> 245) % 10 != 0) return _msgSender();
    address thief = IStaking(staking).randomRoyalOwner(seed >> 128);
    if (thief == address(0x0)) return _msgSender();
    return thief;
  }

  /** RENDER */

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
    return ITraits(traits).tokenURI(tokenId);
  }
}
