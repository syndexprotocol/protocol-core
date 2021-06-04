pragma solidity ^0.8.0;

import "./utils/SafeMathV4.sol";
import "./interfaces/IERC20.sol";
import './interfaces/ISYND.sol';

contract TokenLockup {

    using SafeMath for uint256;
    address public benefactor;
    address public deployer;
    address public constant syndex = 0xe2Fd51755e84D01D865e869F284ae03C995F8f2C;
    uint256 public lastUnlock;
    uint256 public nextUnlock;
    uint256 public constant interval = 7 days;
    uint256 public constant totalCycles = 52; // The lockup is divided into 52 cycles
    uint256 public currentCycle = 0;
    uint256 public unScaledDistributionAmount;
    uint256 public initialScalingFactor;
    bool public initialized = false;
    
    IERC20 _token = IERC20(syndex);

    constructor(address _benefactor) {
        deployer = msg.sender;
        benefactor = _benefactor;
    }
    
    function initialize() public {
        require(msg.sender == deployer);
        require(initialized == false);
        initialized = true;
        lastUnlock = block.timestamp;
        nextUnlock = lastUnlock + interval;
        uint256 balance = _token.balanceOf(address(this));
        initialScalingFactor = ISYND(syndex).syndsScalingFactor();
        uint256 unscaledTotal = balance.mul(1e18).div(initialScalingFactor);
        unScaledDistributionAmount = unscaledTotal/totalCycles;
    }

    function distribute() public // This can be called by anyone and will distribute the tokens to benefactor, as long as Distribution is possible
    {
        require(initialized == true);
        require(block.timestamp >= nextUnlock, "No tokens to distribute yet");
        require(currentCycle < totalCycles, "Distribution Completed"); 
        nextUnlock = nextUnlock + interval;
        currentCycle += 1;
        uint256 currentScalingFactor = ISYND(syndex).syndsScalingFactor();
        uint256 scaledAmount = unScaledDistributionAmount.mul(currentScalingFactor).div(1e18);
        _token.transfer(benefactor, scaledAmount);
    }
    
    function recoverLeftover() public // Only callable once distribute has been called X amount of times (sucessfully), where X is the number of cycles above
    {
        require(currentCycle == totalCycles, "Distribution not completed");
        uint256 leftOverBalance =  _token.balanceOf(address(this));
        _token.transfer(benefactor, leftOverBalance);
    }
}
