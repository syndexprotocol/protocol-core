pragma solidity ^0.6.12;

import './SupplyHandlerRole.sol';
import './interfaces/IAssetOracle.sol';

contract SupplyOracle is SupplyHandlerRole {
    address public assetOracle;
    address public rebaser;
    uint256[] public lastRebaseSupply;
    uint256[] public supply;

    modifier onlyRebaser() {
        require(msg.sender == rebaser, "only Rebaser");
        _;
    }

    constructor(address _assetOracle, uint256[] memory _currentSupplies)
        public
    {
        assetOracle = _assetOracle;
        require(_currentSupplies.length == getTotalAssets());
        supply = _currentSupplies;
        lastRebaseSupply = _currentSupplies;
    }

    function setAssetOracle(address oracle) public onlySupplyHandler {
        assetOracle = oracle;
    }

    function setRebaser(address _rebaser) public onlySupplyHandler {
        rebaser = _rebaser;
    }

    function getTotalAssets() public view returns (uint256) {
        return IAssetOracle(assetOracle).totalAssetCount();
    }

    function addAssetSupply(uint256 _assetSupply) public onlySupplyHandler {
        require(supply.length <= getTotalAssets());
        supply.push(_assetSupply);
    }

    function updateSupply(uint256 index, uint256 _assetSupply)
        public
        onlySupplyHandler
    {
        require(index < getTotalAssets());
        supply[index] = _assetSupply;
    }

    function updateAllSupply(uint256[] memory latestSupplyData)
        public
        onlySupplyHandler
    {
        require(latestSupplyData.length == getTotalAssets()); // Update the supply for every asset
        supply = latestSupplyData;
    }

    function removeSupply(uint256 index) external {
        // Can only be called from Asset Oracle
        require(msg.sender == assetOracle);
        for (uint256 i = index; i < supply.length - 1; i++) {
            supply[i] = supply[i + 1];
            lastRebaseSupply[i] = lastRebaseSupply[i + 1];
        }
        delete supply[supply.length - 1];
        delete lastRebaseSupply[supply.length - 1];
        supply.pop();
        lastRebaseSupply.pop();
    }

    function storeSupply() external onlyRebaser {
        for (uint256 i = 0; i < supply.length - 1; i++) {
            lastRebaseSupply[i] = supply[i];
        }
    }

    function getSupply(uint256 index) public view returns (uint256) {
        return supply[index];
    }

    function getLastRebaseSupply(uint256 index) public view returns (uint256) {
        return lastRebaseSupply[index];
    }

    function totalSupplyCount() public view returns (uint256) {
        return supply.length;
    }
}
