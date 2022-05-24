// SPDX-License-Identifier: Unlicense
// solhint-disable quotes 

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./ITraits.sol";
import "./IHelloGophers.sol";

contract Traits is Ownable, ITraits {

  using Strings for uint16;
  using Strings for uint256;

  struct RoleMetadata {
    string name;
    string description;
  }

  string[7] public statTypes = [
    "Level",
    "HP",
    "MP",
    "Damage",
    "Attack Speed",
    "Armor",
    "Speed"
  ];

  // mapping from trait(appearance) type (index) to its name
  string[5] public appearanceTypes = [
    "Expression",
    "Outfit",
    "Weapon",
    "Skin Color",
    "Background"
  ];

  string public imagePrefix = "";
  string public imageSuffix = ".png";

  mapping(uint256 => RoleMetadata) roles;
  // roleId -> appearanceType -> variation(name)
  mapping(uint256 => mapping(uint256 => mapping(uint256 => string))) public appearanceVariations; 
  mapping(uint256 => string) public hashToImage;

  mapping(uint256 => string) public customGopherAppearanceVariations;
  mapping(uint256 => string) public customGopherImages;

  IHelloGophers public helloGophers;

  /** ADMIN */

  function setHelloGophers(address _helloGophers) external onlyOwner {
    helloGophers = IHelloGophers(_helloGophers);
  }

  function setImagePrefix(string memory _imagePrefix) external onlyOwner {
    imagePrefix = _imagePrefix;
  }

  function setImageSuffix(string memory _imageSuffix) external onlyOwner {
    imageSuffix = _imageSuffix;
  }

  function uploadAppearanceVariations(uint256 roleId, uint256 appearanceType, uint256[] calldata variations, string[] calldata names) external onlyOwner {
    require(appearanceType < appearanceTypes.length, "Invalid appearanceType");
    require(variations.length == names.length, "Mismatched inputs");
    for (uint256 i = 0; i < names.length; i++) {
      appearanceVariations[roleId][appearanceType][variations[i]] = names[i];
    }
  }

  function uploadCustomGopherAppearanceVariations(uint256 tokenId, string calldata name) external onlyOwner {
    require(helloGophers.isCustomGopher(tokenId), "Not custom gopher");

    customGopherAppearanceVariations[tokenId] = name;
  }

  function uploadRoles(uint256[] calldata roleIds, RoleMetadata[] calldata roleMetadata) external onlyOwner {
    require(roleIds.length == roleMetadata.length, "Mismatched inputs");
    for (uint256 i = 0; i < roleMetadata.length; i++) {
      roles[roleIds[i]] = roleMetadata[i];
    }
  }

  function uploadCustomGopherImage(uint256 tokenId, string calldata image) public onlyOwner {
    customGopherImages[tokenId] = image;
  }

  function uploadImage(uint256 appearanceHash, string calldata image) public onlyOwner {
    hashToImage[appearanceHash] = image;
  }

  function uploadCustomGopherImageBulk(uint256[] calldata tokenIds, string[] calldata images) external onlyOwner {
    require(tokenIds.length == images.length, "Mismatched inputs");
    for(uint256 i = 0; i < images.length; i++) {
      uploadCustomGopherImage(tokenIds[i], images[i]);
    }
  }

  function uploadImageBulk(uint256[] calldata appearanceHashes, string[] calldata images) external onlyOwner {
    require(appearanceHashes.length == images.length, "Mismatched inputs");
    for(uint256 i = 0; i < images.length; i++) {
      uploadImage(appearanceHashes[i], images[i]);
    }
  }

  /** RENDER */

  /**
   * generates an attribute for the attributes array in the ERC721 metadata standard
   * @param traitType the trait type to reference as the metadata key
   * @param value the token's trait associated with the key
   * @return a JSON dictionary for the single attribute
   */
  function attributeForTypeAndValue(string memory traitType, string memory value) internal pure returns (string memory) {
    return string(abi.encodePacked(
      '{"trait_type":"',
      traitType,
      '","value":"',
      value,
      '"}'
    ));
  }

  function attributeForTypeAndValue(string memory traitType, uint16 value) internal pure returns (string memory) {
    return string(abi.encodePacked(
      '{"trait_type":"',
      traitType,
      '","value":',
      value.toString(),
      '}'
    ));
  }

  /**
   * generates an array composed of all the individual traits and values
   * @param tokenId the ID of the token to compose the metadata for
   * @return a JSON array of all of the attributes for given token ID
   */
  function compileAttributes(uint256 tokenId) public view returns (string memory) {
    IHelloGophers.Trait memory t = helloGophers.getTokenTraits(tokenId);
    string memory stats = string(abi.encodePacked(
      attributeForTypeAndValue(statTypes[0], t.stat.level), ',',
      attributeForTypeAndValue(statTypes[1], t.stat.hp), ',',
      attributeForTypeAndValue(statTypes[2], t.stat.mp), ',',
      attributeForTypeAndValue(statTypes[3], t.stat.damage), ',',
      attributeForTypeAndValue(statTypes[4], t.stat.atkSpeed), ',',
      attributeForTypeAndValue(statTypes[5], t.stat.armor), ',',
      attributeForTypeAndValue(statTypes[6], t.stat.speed), ','
    ));

    string memory appearances;
    if(helloGophers.isCustomGopher(tokenId)) {
      appearances = string(abi.encodePacked(
        attributeForTypeAndValue(appearanceTypes[0], customGopherAppearanceVariations[tokenId]), ',',
        attributeForTypeAndValue(appearanceTypes[1], customGopherAppearanceVariations[tokenId]), ',',
        attributeForTypeAndValue(appearanceTypes[2], customGopherAppearanceVariations[tokenId]), ',',
        attributeForTypeAndValue(appearanceTypes[3], customGopherAppearanceVariations[tokenId]), ',',
        attributeForTypeAndValue(appearanceTypes[4], customGopherAppearanceVariations[tokenId]), ','
      ));
    } else {
      appearances = string(abi.encodePacked(
        attributeForTypeAndValue(appearanceTypes[0], appearanceVariations[t.roleId][0][t.appearance.expression]), ',',
        attributeForTypeAndValue(appearanceTypes[1], appearanceVariations[t.roleId][1][t.appearance.outfit]), ',',
        attributeForTypeAndValue(appearanceTypes[2], appearanceVariations[t.roleId][2][t.appearance.weapon]), ',',
        attributeForTypeAndValue(appearanceTypes[3], appearanceVariations[t.roleId][3][t.appearance.skinColor]), ',',
        attributeForTypeAndValue(appearanceTypes[4], appearanceVariations[t.roleId][4][t.appearance.background]), ','
      ));
    }
   
    return string(abi.encodePacked(
      '[',
      stats,
      appearances,
      '{"trait_type":"Role","value":"', 
      roles[t.roleId].name,
      '"},{"trait_type":"Generation","value":"',
      tokenId <= helloGophers.getMaxGen0Tokens() ? 'Gen 0' : 'Gen 1',
      '"},{"trait_type":"Class","value":"',
      t.isPeasant ? "Peasant" : "Royal",
      '"}]'
    ));
  }

  function getImage(uint256 tokenId) public view returns(string memory) {
    return string(abi.encodePacked(
      imagePrefix, 
      helloGophers.isCustomGopher(tokenId) 
        ? customGopherImages[tokenId] 
        : hashToImage[helloGophers.getAppearanceHash(tokenId)], 
      imageSuffix
    ));
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    IHelloGophers.Trait memory t = helloGophers.getTokenTraits(tokenId);

    string memory metadata = string(abi.encodePacked(
      '{"name": "',
      t.isPeasant ? 'Peasant #' : 'Royal #',
      tokenId.toString(),
      '", "description": "',
      roles[t.roleId].description,
      '", "image": "',
      getImage(tokenId),
      '", "attributes":',
      compileAttributes(tokenId),
      "}"
    ));

    return string(abi.encodePacked(
      "data:application/json;base64,",
      base64(bytes(metadata))
    ));
  }

  /** BASE 64 - Written by Brech Devos */
  
  string internal constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function base64(bytes memory data) internal pure returns (string memory) {
    if (data.length == 0) return '';
    
    // load the table into memory
    string memory table = TABLE;

    // multiply by 4/3 rounded up
    uint256 encodedLen = 4 * ((data.length + 2) / 3);

    // add some extra buffer at the end required for the writing
    string memory result = new string(encodedLen + 32);

    assembly {
      // set the actual output length
      mstore(result, encodedLen)
      
      // prepare the lookup table
      let tablePtr := add(table, 1)
      
      // input ptr
      let dataPtr := data
      let endPtr := add(dataPtr, mload(data))
      
      // result ptr, jump over length
      let resultPtr := add(result, 32)
      
      // run over the input, 3 bytes at a time
      for {} lt(dataPtr, endPtr) {}
      {
          dataPtr := add(dataPtr, 3)
          
          // read 3 bytes
          let input := mload(dataPtr)
          
          // write 4 characters
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr( 6, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(        input,  0x3F)))))
          resultPtr := add(resultPtr, 1)
      }
      
      // padding with '='
      switch mod(mload(data), 3)
      case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
      case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
    }
    
    return result;
  }
}