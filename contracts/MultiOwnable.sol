pragma solidity >=0.4.21 <0.6.0;

/**
 * @author Wallet Now
 * @title MultiOwnableMultiOwnable
 * @dev Allows the implementing contract to have multiple owner addresses.
 */
contract MultiOwnable {

    mapping (uint256 => address) public __owners;
    uint256 public __ownersQuantity;

    /**
     * @dev Emitted when the owner is changed
     * @param _newOwners Addresses of the new owners
     */
    event OwnershipTransferred(address[] _newOwners);

    modifier onlyOwner() {
        uint256 qty = __ownersQuantity;
        // Please notice that while no owners are defined, it is 100% public
        // This means that the ownership must be set IMMEDIATELY after deploying the contract
        // We also can't set this at the contructor since this must work thru a proxy
        if (qty > 0) {
            bool found = false;
            for (uint256 index = 0; index < qty; index++) {
                if (__owners[index] == msg.sender) {
                    found = true;
                    break;
                }
            }
            require(found == true, "OwnerRole: caller does not have the Owner role");
        }
        _;
    }

    /**
     * @dev Allows the current owners to transfer ownership
     * @param _newOwners The addresses to transfer ownership to
     */
    function transferOwnership(address[] memory _newOwners) public onlyOwner {
        // Migrations MUST call this method immediately after deployment of V1.
        //
        // The ownership can only be defined right after the deployment or
        // by the owners themselves.
        // 
        // IMPORTANT: The owner must not be set in the constructor since it would not work from a proxy
        // call.
        uint256 qty = _newOwners.length;
        __ownersQuantity = qty;
        for (uint256 index = 0; index < qty; index++) {
            require(_newOwners[index] != address(0), "Can't set ZERO address as owner");
            __owners[index] = _newOwners[index];
        }
        emit OwnershipTransferred(_newOwners);
    }
}
