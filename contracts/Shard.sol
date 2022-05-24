// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Shard is ERC20, Ownable {

  // a mapping from an address to whether or not it can mint / burn
  mapping(address => bool) public controllers;

  constructor() ERC20("SHARD", "SHARD") {}

  function mint(address to, uint256 amount) external {
    require(controllers[msg.sender], "Only controllers can mint.");
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    require(controllers[msg.sender], "Only controllers can burn.");
    _burn(from, amount);
  }

  function addController(address controller) external onlyOwner {
    controllers[controller] = true;
  }

  function removeController(address controller) external onlyOwner {
    controllers[controller] = false;
  }
}