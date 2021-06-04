pragma solidity >=0.5.12;

import "../interfaces/AggregatorV3Interface.sol";

contract ChainlinkOracle {
    constructor() public {}

    function getLatestPrice(address oracle)
        public
        view
        returns (bool, uint256)
    {
        // if the round is not completed, updated at is 0
        (, int256 answer, , uint256 updatedAt, ) =
            AggregatorV3Interface(oracle).latestRoundData();
        return (updatedAt != 0, uint256(answer));
    }
}
