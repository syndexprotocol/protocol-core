pragma solidity 0.5.16;

import "./oracles/PancakeOracle.sol";
import "./BasicRebaser.sol";

contract Rebaser is BasicRebaser, PancakeOracle {
    constructor(
        address token,
        address _mCapOracle,
        address _assetOracle,
        address _supplyOracle,
        address _treasury
    )
        public
        BasicRebaser(token, _mCapOracle, _assetOracle, _supplyOracle, _treasury)
        PancakeOracle(token)
    {}
}
