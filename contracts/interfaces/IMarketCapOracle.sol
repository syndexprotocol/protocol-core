pragma solidity 0.5.16;

interface IMarketCapOracle {
    function targetPrice() external view returns (uint256);
}