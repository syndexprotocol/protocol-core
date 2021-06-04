pragma solidity 0.5.16;

interface IPoolEscrow {
    function notifySecondaryDistributor(uint256 number) external;

    function notifySecondaryTokens(uint256 number) external;
}
