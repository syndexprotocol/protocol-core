pragma solidity 0.5.16;

import "./utils/SafeMathV2.sol";
import "./utils/Address.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISYND.sol";
import "./interfaces/IMarketCapOracle.sol";
import "./interfaces/IAssetOracle.sol";
import "./interfaces/ISupplyOracle.sol";
import "./interfaces/IPoolEscrow.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract BasicRebaser {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Updated(uint256 syndex);
    event NoUpdateSYND();
    event NoSecondaryMint();
    event NoRebaseNeeded();
    event StillCold();
    event NotInitialized();

    uint256 public constant BASE = 1e18;
    uint256 public constant WINDOW_SIZE = 48;

    address public syndex;
    address public assetOracle;
    address public supplyOracle;
    address public mCapOracle;
    uint256[] public pricesSYND = new uint256[](WINDOW_SIZE);
    uint256 public averageSYND;
    uint256 public lastUpdate;
    uint256 public frequency = 1 minutes;
    uint256 public counter = 0;
    uint256 public epoch = 1;
    uint256 public positiveRebaseLimitBasisPoints = 750; // 7.5% by default
    uint256 public negativeRebaseLimitBasisPoints = 750; // 7.5% by default
    uint256 public constant basisBase = 10000; // 100%
    address public secondaryDistributor;
    address public governance;

    uint256 public nextRebase = 0;
    uint256 public constant REBASE_DELAY = WINDOW_SIZE * 30 minutes;
    IUniswapV2Pair public constant UNIPAIR =
        IUniswapV2Pair(0xAcfCc6DD9292d08ff7DDA8713b611014178e2593);

    modifier onlyGov() {
        require(msg.sender == governance, "only gov");
        _;
    }

    constructor(
        address token,
        address _mCapOracle,
        address _assetOracle,
        address _supplyOracle,
        address _secondaryDistributor
    ) public {
        syndex = token;
        mCapOracle = _mCapOracle;
        assetOracle = _assetOracle;
        supplyOracle = _supplyOracle;
        secondaryDistributor = _secondaryDistributor;
        governance = msg.sender;
    }

    function setNextRebase(uint256 next) external onlyGov {
        require(nextRebase == 0, "Only one time activation");
        nextRebase = next;
    }

    function setGovernance(address account) external onlyGov {
        governance = account;
    }

    function setSecondaryDistribution(address pool) external onlyGov {
        secondaryDistributor = pool;
    }

    function setAssetOracle(address oracle) external onlyGov {
        assetOracle = oracle;
    }

    function setSupplyOracle(address oracle) external onlyGov {
        supplyOracle = oracle;
    }

    function setMCapOracle(address oracle) external onlyGov {
        mCapOracle = oracle;
    }

    function setFrequency(uint256 _minutes) external onlyGov {
        frequency = _minutes * 1 minutes;
    }

    function setRebaseLimit(uint256 _limit, bool positive) external onlyGov {
        require(500 <= _limit && _limit <= 2500); // 5% to 25%
        if (positive) positiveRebaseLimitBasisPoints = _limit;
        else negativeRebaseLimitBasisPoints = _limit;
    }

    function checkRebase() external {
        // syndex ensures that we do not have smart contracts rebasing
        require(msg.sender == address(syndex), "only through syndex token");
        rebase();
        recordPrice();
    }

    function recordPrice() public {
        if (msg.sender != tx.origin && msg.sender != address(syndex)) {
            // smart contracts could manipulate data via flashloans,
            // thus we forbid them from updating the price
            return;
        }

        if (block.timestamp < lastUpdate + frequency) {
            // addition is running on timestamps, this will never overflow
            // we leave at least the specified period between two updates
            return;
        }
        IAssetOracle(assetOracle).recordAssetPrice();

        (bool success, uint256 priceSYND) = getPriceSYND();
        if (!success) {
            // price of SYND was not returned properly
            emit NoUpdateSYND();
            return;
        }
        lastUpdate = block.timestamp;

        if (counter < WINDOW_SIZE) {
            // still in the warming up phase
            averageSYND = averageSYND.mul(counter).add(priceSYND).div(
                counter.add(1)
            );
            pricesSYND[counter] = priceSYND;
            counter++;
        } else {
            uint256 index = counter % WINDOW_SIZE;
            averageSYND = averageSYND
                .mul(WINDOW_SIZE)
                .sub(pricesSYND[index])
                .add(priceSYND)
                .div(WINDOW_SIZE);
            pricesSYND[index] = priceSYND;
            counter++;
        }
        emit Updated(priceSYND);
    }

    function rebase() public {
        // make public rebasing only after initialization
        if (nextRebase == 0 && msg.sender != governance) {
            emit NotInitialized();
            return;
        }
        if (counter <= WINDOW_SIZE && msg.sender != governance) {
            emit StillCold();
            return;
        }
        if (block.timestamp < nextRebase) {
            return;
        } else {
            nextRebase = nextRebase + REBASE_DELAY;
        }

        ISupplyOracle(supplyOracle).storeSupply();
        IAssetOracle(assetOracle).updateOnRebase();

        uint256 targetPrice = IMarketCapOracle(mCapOracle).targetPrice();
        // only rebase if there is a 5% difference between the Target Price and SYND
        uint256 highThreshold = targetPrice.mul(105).div(100);
        uint256 lowThreshold = targetPrice.mul(95).div(100);

        if (averageSYND > highThreshold) {
            // SYND is too expensive, this is a positive rebase increasing the supply
            uint256 factor =
                BASE.sub(
                    BASE.mul(averageSYND.sub(targetPrice)).div(
                        averageSYND.mul(10)
                    )
                );
            uint256 increase = BASE.sub(factor);
            uint256 realAdjustment = increase.mul(BASE).div(factor);
            uint256 currentSupply = IERC20(syndex).totalSupply();
            uint256 desiredSupply =
                currentSupply.add(currentSupply.mul(realAdjustment).div(BASE));
            uint256 upperLimit =
                currentSupply
                    .mul(basisBase.add(positiveRebaseLimitBasisPoints))
                    .div(basisBase);
            if (desiredSupply > upperLimit)
                // Increase expected rebase is above the limit
                desiredSupply = upperLimit;
            uint256 secondaryDistributionBudget =
                desiredSupply.sub(currentSupply).mul(10).div(100);
            desiredSupply = desiredSupply.sub(secondaryDistributionBudget);

            // Cannot underflow as desiredSupply > currentSupply, the result is positive
            // delta = (desiredSupply / currentSupply) * 100 - 100
            uint256 delta =
                desiredSupply.mul(BASE).div(currentSupply).sub(BASE);
            ISYND(syndex).rebase(epoch, delta, true);

            if (secondaryDistributor != address(0)) {
                // notify the pool escrow that tokens are available
                ISYND(syndex).mint(address(this), secondaryDistributionBudget);
                IERC20(syndex).safeApprove(secondaryDistributor, 0);
                IERC20(syndex).safeApprove(
                    secondaryDistributor,
                    secondaryDistributionBudget
                );
                IPoolEscrow(secondaryDistributor).notifySecondaryDistributor(
                    secondaryDistributionBudget
                );
            } else {
                emit NoSecondaryMint();
            }
            UNIPAIR.sync();
            epoch++;
        } else if (averageSYND < lowThreshold) {
            // SYND is too cheap, this is a negative rebase decreasing the supply
            uint256 factor =
                BASE.add(
                    BASE.mul(targetPrice.sub(averageSYND)).div(
                        averageSYND.mul(10)
                    )
                );
            uint256 increase = factor.sub(BASE);
            uint256 realAdjustment = increase.mul(BASE).div(factor);
            uint256 currentSupply = IERC20(syndex).totalSupply();
            uint256 desiredSupply =
                currentSupply.sub(currentSupply.mul(realAdjustment).div(BASE));
            uint256 lowerLimit =
                currentSupply
                    .mul(basisBase.sub(negativeRebaseLimitBasisPoints))
                    .div(basisBase);
            if (desiredSupply < lowerLimit)
                // Decrease expected rebase is below the limit
                desiredSupply = lowerLimit;
            // Cannot overflow as desiredSupply < currentSupply
            // delta = 100 - (desiredSupply / currentSupply) * 100
            uint256 delta =
                uint256(BASE).sub(desiredSupply.mul(BASE).div(currentSupply));
            ISYND(syndex).rebase(epoch, delta, false);
            UNIPAIR.sync();
            epoch++;
        } else {
            // else the price is within bounds
            emit NoRebaseNeeded();
        }
    }

    /**
     * Calculates how a rebase would look if it was triggered now.
     */
    function calculateRealTimeRebase() public view returns (uint256, uint256) {
        // only rebase if there is a 5% difference between the price of Target price and SYND
        uint256 targetPrice = IMarketCapOracle(mCapOracle).targetPrice();
        uint256 highThreshold = targetPrice.mul(105).div(100);
        uint256 lowThreshold = targetPrice.mul(95).div(100);

        if (averageSYND > highThreshold) {
            // SYND is too expensive, this is a positive rebase increasing the supply
            uint256 factor =
                BASE.sub(
                    BASE.mul(averageSYND.sub(targetPrice)).div(
                        averageSYND.mul(10)
                    )
                );
            uint256 increase = BASE.sub(factor);
            uint256 realAdjustment = increase.mul(BASE).div(factor);
            uint256 currentSupply = IERC20(syndex).totalSupply();
            uint256 desiredSupply =
                currentSupply.add(currentSupply.mul(realAdjustment).div(BASE));
            uint256 upperLimit =
                currentSupply
                    .mul(basisBase.add(positiveRebaseLimitBasisPoints))
                    .div(basisBase);
            if (desiredSupply > upperLimit)
                // Increase expected rebase is above the limit
                desiredSupply = upperLimit;
            uint256 secondaryDistributionBudget =
                desiredSupply.sub(currentSupply).mul(10).div(100);
            desiredSupply = desiredSupply.sub(secondaryDistributionBudget);

            // Cannot underflow as desiredSupply > currentSupply, the result is positive
            // delta = (desiredSupply / currentSupply) * 100 - 100
            uint256 delta =
                desiredSupply.mul(BASE).div(currentSupply).sub(BASE);
            return (
                delta,
                secondaryDistributor == address(0)
                    ? 0
                    : secondaryDistributionBudget
            );
        } else if (averageSYND < lowThreshold) {
            // SYND is too cheap, this is a negative rebase decreasing the supply
            uint256 factor =
                BASE.add(
                    BASE.mul(targetPrice.sub(averageSYND)).div(
                        targetPrice.mul(10)
                    )
                );
            uint256 increase = factor.sub(BASE);
            uint256 realAdjustment = increase.mul(BASE).div(factor);
            uint256 currentSupply = IERC20(syndex).totalSupply();
            uint256 desiredSupply =
                currentSupply.sub(currentSupply.mul(realAdjustment).div(BASE));
            uint256 lowerLimit =
                currentSupply
                    .mul(basisBase.sub(negativeRebaseLimitBasisPoints))
                    .div(basisBase);
            if (desiredSupply < lowerLimit)
                // Decrease expected rebase is below the limit
                desiredSupply = lowerLimit;
            // Cannot overflow as desiredSupply < currentSupply
            // delta = 100 - (desiredSupply / currentSupply) * 100
            uint256 delta =
                uint256(BASE).sub(desiredSupply.mul(BASE).div(currentSupply));
            return (delta, 0);
        } else {
            return (0, 0);
        }
    }

    function getPriceSYND() public view returns (bool, uint256);
}
