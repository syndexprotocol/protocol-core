pragma solidity ^0.5.0;

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
}
