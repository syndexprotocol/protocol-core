pragma solidity 0.5.16;

import "../interfaces/IPancakeRouter02.sol";
import '../utils/SafeMathV2.sol';

contract PancakeOracle {
    using SafeMath for uint256;

    address public constant oracle = 0xc18Ff0ec2461b5F9F0a258c702C7206397143A96;
    address public constant usdc = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;
    address public constant weth = 0x58AbBb3c89750dDA42b65822042EbADb00f9Ef61;
    address public syndex;
    address[] public path;

    constructor(address token) public {
        syndex = token;
        path = [syndex, weth, usdc];
    }

    function getPriceSYND() public view returns (bool, uint256) {
        uint256[] memory amounts =
            IPancakeRouter02(oracle).getAmountsOut(1e18, path);
        return (syndex != address(0), amounts[2]);
    }
}
