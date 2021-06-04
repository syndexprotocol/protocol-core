pragma solidity >=0.5.16;

interface ISYND {
  function rebase(uint256 epoch, uint256 supplyDelta, bool positive) external;
  function mint(address to, uint256 amount) external;
    function syndsScalingFactor() external view returns(uint256);
}