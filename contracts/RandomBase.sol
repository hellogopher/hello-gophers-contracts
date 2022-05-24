// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract RandomBase {

  uint256 private seedNonce;

  function vrf() private view returns (bytes32 result) {
    uint[1] memory bn;
    bn[0] = block.number;
    assembly {
      let memPtr := mload(0x40)
      if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
        invalid()
      }
      result := mload(memPtr)
    }
  }

  function random() internal returns (uint256) {
    uint256 rand = uint256(keccak256(abi.encode(vrf(), seedNonce)));
    seedNonce++;
    return rand;
  }
}