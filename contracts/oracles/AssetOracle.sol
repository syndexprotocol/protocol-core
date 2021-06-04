pragma solidity ^0.6.12;

import "../interfaces/ISupplyOracle.sol";
import "./ChainlinkOracle.sol";
import "../utils/SafeMathV3.sol";

contract AssetOracle is ChainlinkOracle {
    using SafeMath for uint256;

    event RecordedPrices();

    struct Asset {
        string name;
        address oracle;
    }

    address public pendingGov;
    address public rebaser;
    address public governor;
    address public supplyOracle;
    uint256 public WINDOW_SIZE = 48;
    uint256 public counter = 0;
    uint256[] public averagePrice;
    uint256[][] public recentPrice;
    uint256[] public lastRebasePrice;

    Asset[] public assets;

    modifier onlyGov() {
        require(msg.sender == governor, "only gov");
        _;
    }

    modifier onlyRebaser() {
        require(msg.sender == rebaser, "only rebaser");
        _;
    }

    constructor() public {
        governor = msg.sender;
    }

    function _setPendingGov(address pendingGov_) external onlyGov {
        pendingGov = pendingGov_;
    }

    function _acceptGov() external {
        require(msg.sender == pendingGov, "!pending");
        governor = pendingGov;
        pendingGov = address(0);
    }

    function setSupplyOracle(address _supplyOracle) public onlyGov {
        supplyOracle = _supplyOracle;
    }

    function setRebaser(address _rebaser) public {
        rebaser = _rebaser;
    }

    function addAsset(string memory _name, address _oracle) public onlyGov {
        Asset memory newAsset = Asset({name: _name, oracle: _oracle});
        assets.push(newAsset);
        averagePrice.push();
        recentPrice.push();
        lastRebasePrice.push(getAssetPrice(assets.length - 1));
    }

    function deleteAsset(uint256 index) public onlyGov {
        require(supplyOracle != address(0));
        uint256 assetLength = assets.length;
        for (uint256 i = index; i < assetLength - 1; i++) {
            assets[i] = assets[i + 1];
            averagePrice[i] = averagePrice[i + 1];
            lastRebasePrice[i] = lastRebasePrice[i + 1];
            recentPrice[i] = recentPrice[i + 1];
        }
        delete assets[assetLength - 1];
        delete averagePrice[assetLength - 1];
        delete lastRebasePrice[assetLength - 1];
        delete recentPrice[assetLength - 1];
        assets.pop();
        averagePrice.pop();
        lastRebasePrice.pop();
        recentPrice.pop();
        ISupplyOracle(supplyOracle).removeSupply(index);
    }

    function getAsset(uint256 index)
        public
        view
        returns (string memory, address)
    {
        Asset memory p = assets[index];
        return (p.name, p.oracle);
    }

    function getAssetPrice(uint256 index) public view returns (uint256) {
        (bool success, uint256 assetPrice) =
            getLatestPrice(assets[index].oracle);
        require(success == true);
        return assetPrice;
    }

    function updateOnRebase() external onlyRebaser {
        lastRebasePrice = averagePrice;
    }

    function recordAssetPrice() external onlyRebaser {
        if (counter < WINDOW_SIZE) {
            // still in the warming up phase
            for (uint256 i = 0; i < assets.length; i++) {
                uint256 currentPrice = getAssetPrice(i);
                averagePrice[i] = averagePrice[i]
                    .mul(counter)
                    .add(currentPrice)
                    .div(counter.add(1));
                recentPrice[i].push(currentPrice);
            }
            counter++;
        } else {
            uint256 index = counter % WINDOW_SIZE;
            for (uint256 i = 0; i < assets.length; i++) {
                uint256 currentPrice = getAssetPrice(i);
                averagePrice[i] = averagePrice[i]
                    .mul(WINDOW_SIZE)
                    .sub(recentPrice[i][index])
                    .add(currentPrice)
                    .div(WINDOW_SIZE);
                recentPrice[i][index] = currentPrice;
            }
            counter++;
        }
        emit RecordedPrices();
    }

    function getAveragePrice(uint256 index) public view returns (uint256) {
        return averagePrice[index];
    }

    function getLastRebasePrice(uint256 index) public view returns (uint256) {
        return lastRebasePrice[index];
    }

    function totalAssetCount() public view returns (uint256) {
        return assets.length;
    }
}
