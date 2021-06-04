pragma solidity 0.5.16;

contract IPancakeRouter02 {
    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        returns (uint256[] memory amounts);
}
