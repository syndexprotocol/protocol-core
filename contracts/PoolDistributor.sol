pragma solidity 0.5.16;

import "./utils/Math.sol";
import "./utils/SafeMathV2.sol";
import "./utils/Address.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Mintable.sol";
import './interfaces/IPoolEscrow.sol';

contract PoolDistributor {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    modifier onlyGov() {
        require(msg.sender == governance, "only governance");
        _;
    }

    address public synd;
    address public governance;
    address[] public pools;
    uint256[] public distributionPercent = [300, 300, 300, 100]; // Percentages are stored in basis points

    constructor(
        address _firstPool,
        address _secondPool,
        address _thirdPool,
        address _bountyPool,
        address _synd
    ) public {
        pools.push(_firstPool);
        pools.push(_secondPool);
        pools.push(_thirdPool);
        pools.push(_bountyPool);
        synd = _synd;
        governance = msg.sender;
    }

    function setPoolAddress(uint256 index, address _newAddress) public onlyGov {
        // 1-4 for the above pools
        pools[index] = _newAddress;
    }

    function addPool(address _newPool) public onlyGov {
        pools.push(_newPool);
        distributionPercent.push(0); // by default newly added pools have 0% Percentage allocation
    }

    function setPercentages(uint256[] memory newPercent) public onlyGov {
        uint256 sum = 0;
        for (uint256 i = 0; i < newPercent.length; i++)
            sum = sum + newPercent[i];
        require(sum == 1000, "Distribution should be 10%");
        require(
            newPercent.length == pools.length,
            "Percentage array length needs to be equal to pools count"
        );
        distributionPercent = newPercent;
    }

    function notifySecondaryDistributor(uint256 tax) external {
        IERC20(synd).safeTransferFrom(msg.sender, address(this), tax);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 distributionAmount =
                tax.mul(distributionPercent[i]).div(1000);
            IERC20(synd).safeApprove(pools[i], distributionAmount);
            IPoolEscrow(pools[i]).notifySecondaryTokens(distributionAmount);
        }
    }
}
