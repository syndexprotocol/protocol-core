pragma solidity ^0.6.12;

import "../interfaces/IAssetOracle.sol";
import "../interfaces/ISupplyOracle.sol";
import "../utils/SafeMathV3.sol";

contract MarketCapOracle {
    using SafeMath for uint256;

    uint256 public constant BASE = 1e18;
    uint256 public constant divisionFactor = 1e3;
    address public governor;
    uint256 public pausedAt = 0;
    uint256 public pauseDelay = 28800; // 5 Days
    IAssetOracle public assetOracle;
    ISupplyOracle public supplyOracle;
    uint256[] public manualWeighting;

    modifier onlyGov() {
        require(msg.sender == governor, "only gov");
        _;
    }

    constructor(address _assetOracle, address _supplyOracle) public {
        governor = msg.sender;
        assetOracle = IAssetOracle(_assetOracle);
        supplyOracle = ISupplyOracle(_supplyOracle);
    }

    function setGovernor(address _newGov) public onlyGov {
        governor = _newGov;
    }

    function setAssetOracle(address oracle) external onlyGov {
        assetOracle = IAssetOracle(oracle);
    }

    function setSupplyOracle(address oracle) external onlyGov {
        supplyOracle = ISupplyOracle(oracle);
    }

    function getPercentageChange(uint256 oldValue, uint256 newValue)
        public
        pure
        returns (uint256, bool)
    {
        uint256 change = 0;
        if (oldValue < newValue) {
            change = BASE.mul(newValue.sub(oldValue)).mul(100).div(oldValue);
            return (change, true);
        } else {
            change = BASE.mul(oldValue.sub(newValue)).mul(100).div(oldValue);
            return (change, false);
        }
    }

    function setManualWeighting(uint256[] memory weights) public onlyGov {
        require(weights.length == assetOracle.totalAssetCount());
        manualWeighting = weights;
        pausedAt = block.number;
    }

    function setPauseDelay(uint256 _newDelay) public onlyGov {
        require(_newDelay >= 5760 && _newDelay <= 40320); // Between 1 to 7 days
        pauseDelay = _newDelay;
    }

    function weightingPaused() public view returns (bool) {
        if (block.number > pausedAt.add(pauseDelay)) {
            return false;
        }
        return true;
    }

    function getMarketCap(uint256 index) public view returns (uint256) {
        uint256 price = assetOracle.getAveragePrice(index);
        uint256 supply = supplyOracle.getSupply(index);
        uint256 mcap = price.mul(supply);
        return mcap;
    }

    function totalMarketCap() public view returns (uint256) {
        uint256 totalAssets = assetOracle.totalAssetCount();
        uint256 totalSupplyCount = supplyOracle.totalSupplyCount();
        require(totalAssets == totalSupplyCount);
        uint256 total = 0;
        for (uint256 i = 0; i < totalAssets; i++) {
            total += getMarketCap(i);
        }
        return total;
    }

    function mCapWeighting(uint256 index) public view returns (uint256) {
        return BASE.mul(getMarketCap(index)).div(totalMarketCap());
    }

    function syndexWeighting(uint256 index) public view returns (uint256) {
        if (!weightingPaused()) {
            return
                (BASE.div(assetOracle.totalAssetCount())).mul(BASE).div(
                    mCapWeighting(index)
                );
        }
        return manualWeighting[index];
    }

    function priceImpact(uint256 index) public view returns (uint256, bool) {
        uint256 oldMcap =
            assetOracle.getLastRebasePrice(index).mul(
                supplyOracle.getLastRebaseSupply(index)
            );
        uint256 currentMcap = getMarketCap(index);
        uint256 updatedTotalMcap =
            totalMarketCap().sub(oldMcap).add(currentMcap);
        return getPercentageChange(totalMarketCap(), updatedTotalMcap);
    }

    function weightedPriceImpact(uint256 index)
        public
        view
        returns (uint256, bool)
    {
        (uint256 percent, bool positive) = priceImpact(index);
        uint256 impact = percent.mul(syndexWeighting(index)).div(BASE);
        return (impact, positive);
    }

    function weightedTotalCap() public view returns (uint256) {
        uint256 totalAssets = assetOracle.totalAssetCount();
        uint256 total = totalMarketCap();
        for (uint256 i = 0; i < totalAssets; i++) {
            (uint256 assetImpact, bool positive) = weightedPriceImpact(i);
            if (positive) {
                uint256 multiplier = BASE.add(assetImpact.div(100));
                total = total.mul(multiplier).div(BASE);
            } else {
                uint256 multiplier = BASE.sub(assetImpact.div(100));
                total = total.mul(multiplier).div(BASE);
            }
        }
        return total;
    }

    function targetPrice() public view returns (uint256) {
        return weightedTotalCap() / divisionFactor;
    }
}
