pragma solidity >=0.5.0;

import "./utils/Roles.sol";

contract SupplyHandlerRole {
    using Roles for Roles.Role;

    event SupplyHandlerAdded(address indexed account);
    event SupplyHandlerRemoved(address indexed account);

    Roles.Role private _supplyHandler;

    constructor() public {
        _addSupplyHandler(msg.sender);
    }

    modifier onlySupplyHandler() {
        require(
            isSupplyHandler(msg.sender),
            "SupplyHandlerRole: caller does not have the SupplyHandler role"
        );
        _;
    }

    function isSupplyHandler(address account) public view returns (bool) {
        return _supplyHandler.has(account);
    }

    function addSupplyHandler(address account) public onlySupplyHandler {
        _addSupplyHandler(account);
    }

    function renounceSupplyHandler() public {
        _removeSupplyHandler(msg.sender);
    }

    function _addSupplyHandler(address account) internal {
        _supplyHandler.add(account);
        emit SupplyHandlerAdded(account);
    }

    function _removeSupplyHandler(address account) internal {
        _supplyHandler.remove(account);
        emit SupplyHandlerRemoved(account);
    }
}
