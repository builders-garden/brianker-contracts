// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import "@openzeppelin/token/ERC20/ERC20.sol";
contract Briankerc20 is ERC20 {
    
    constructor(string memory name, string memory symbol)ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000e18);
    }
    
}
