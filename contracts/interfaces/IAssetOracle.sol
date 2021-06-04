pragma solidity >=0.5.16;

interface IAssetOracle {
    function totalAssetCount() external view returns (uint256);

    function getAssetPrice(uint256 index) external view returns (uint256);

    function getAveragePrice(uint256 index) external view returns (uint256);

    function getLastRebasePrice(uint256 index) external view returns (uint256);

    function updateOnRebase() external;

    function recordAssetPrice() external;
}
