pragma solidity >=0.5.16;

interface ISupplyOracle {
    function totalSupplyCount() external view returns (uint256);

    function getSupply(uint256 index) external view returns (uint256);

    function getLastRebaseSupply(uint256 index) external view returns (uint256);

    function removeSupply(uint256 index) external;

    function storeSupply() external;
}
