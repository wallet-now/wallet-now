pragma solidity >=0.4.21 <0.6.0;

import "./SafeMath.sol";
import "./Address.sol";
import './MultiOwnable.sol';

/**
 * @author Wallet Now
 * @title WalletNow_V1
 * @dev Main Wallet Now contract
 */
contract WalletNow_V1 is MultiOwnable {
    using SafeMath for uint256;

    uint256 constant ONE_MONTH_IN_SECONDS = 60 * 60 * 24 * 30;
    uint256 constant MAX_PURCHASE_MONTHS = 12;

    /*
      Persistence: Avoid using structs as much as possible because this is an upgradable
      contract. If we use structs and change/add/remove any fields, it may missalign memory
     */
    uint256 devsQty;
    mapping (uint256 => address payable) public devs;
    mapping (address => uint256) public devsPercentage;
    mapping (uint256 => uint256) public planMonthlyPrice;
    mapping (address => uint256) public lastPurchasedPlan;
    mapping (address => uint256) public lastPurchasedTimestamp;
    mapping (address => uint256) public planExpiration;
    mapping (address => uint256) public totalDeposited;
    mapping (uint256 => uint256) public featureBounties;

    /*
      Events
     */
    event PlanPriceChanged(uint256 plan, uint256 previousPrice, uint256 newPrice);
    event PlanChanged(address addr, uint256 previousPlan, uint256 newPlan, uint256 newExpiration);
    event FeatureBountyOffered(address addr, uint256 featureId, uint256 bountyAdded, uint256 totalBounty);

    /*
      Public APIs
     */

    /**
     * @dev Sets the percentage of funds to be directed towards the given devs.
     * This is used to save gas when setting multiple percentages at once.
     * @param _percentages list with even number of items, where odds are owner addresses and evens are percentages
     */
    function setDevsPercentage(uint256[] memory _percentages) public onlyOwner {
        uint256 total = 0;
        for (uint256 index = 0; index < _percentages.length; index += 2) {
            uint256 devIndex = index.div(2);
            address payable dev = address(_percentages[index]);
            uint256 percentage = _percentages[index + 1];
            total += percentage;
            devs[devIndex] = dev;
            devsPercentage[dev] = percentage;
        }
        require(total == 100, "Total percentage across all devs must be exactly 100%");
        devsQty = _percentages.length.div(2);
    }

    /**
     * @dev Sets the monthly price of a plan
     * @param _plan plan number
     * @param _price price in BNB
     */
    function setMonthlyPrice(uint256 _plan, uint256 _price) public onlyOwner {
        uint256 previousPrice = planMonthlyPrice[_plan];
        planMonthlyPrice[_plan] = _price;
        emit PlanPriceChanged(_plan, previousPrice, _price);
    }

    /**
     * @dev Sets the monthly price of mutiple plans. Used to save gas when setting multiple
     * @param _prices list with even number of items, where odds are plan numbers and evens are prices in BNB
     */
    function setMonthlyPrices(uint256[] memory _prices) public onlyOwner {
        for (uint256 index = 0; index < _prices.length; index+=2) {
            setMonthlyPrice(_prices[index], _prices[index + 1]);
        }
    }

    /**
     * @dev Purchases, refills or changes sender's account plan
     * @param _plan plan number
     * @return _expiration: New plan expiration date
     */
    function purchasePlan(uint256 _plan) public payable returns (uint256 _expiration) {
        _purchase(msg.sender, _plan, msg.value);
        _deposit(msg.sender, msg.value);
        _expiration = planExpiration[msg.sender];
    }

    /**
     * @dev Calculates what will be the new expiration date if the given account purchases a given plan
     * @param _account account
     * @param _plan plan number
     * @param _amount amount to purchase or refill
     */
    function getNewExpiration(address _account, uint256 _plan, uint256 _amount) public view returns (uint256 _newExpiration) {
        uint256 monthlyPrice = planMonthlyPrice[_plan];
        require(monthlyPrice != 0, "Invalid plan");
        require(_amount >= monthlyPrice, "Can't purchase less than one month");
        
        uint256 previousPlan = lastPurchasedPlan[_account];
        uint256 previousExpiration = planExpiration[_account];
        // Notice that "months" here has zero decimals on purpose
        // you can only purchase in exact on-month increments
        uint256 months = _amount.div(monthlyPrice);
        require(months <= MAX_PURCHASE_MONTHS, "Can't exceed max purchase period");
        if (months >= 10) {
            // Bonus: When purchsaing 10 months, you get 2 free
            months = 12;
        }
        uint256 remainingSeconds = previousExpiration <= block.timestamp ? 0 : previousExpiration.sub(block.timestamp);
        uint256 carryOverSeconds = 0;
        if (remainingSeconds > 0) {
            // Current plan is still valid - calculate the proportional carry-over
            uint256 previousPrice = planMonthlyPrice[previousPlan];
            carryOverSeconds = remainingSeconds.mul(previousPrice).div(monthlyPrice);
        }
        _newExpiration = block.timestamp.add(months.mul(ONE_MONTH_IN_SECONDS)).add(carryOverSeconds);
    }

    /**
     * @dev Gets information about an account's plan
     * @param _account account address
     * @return _activePlan: Currently active plan number;
     *         _lastPurchasedPlan: Last purchased plan number;
     *         _expiration: Plan expiration date;
     */
    function getAccountPlanInfo(address _account) public view
        returns (uint256 _activePlan, uint256 _lastPurchasedPlan, uint256 _expiration) {

        _lastPurchasedPlan = lastPurchasedPlan[_account];
        _expiration = planExpiration[_account];
        _activePlan = (_expiration <= block.timestamp) ? 0 : _lastPurchasedPlan;
    }

    /**
     * @dev Adds a BNB bounty to a feature request
     * @param _featureId feature id
     */
    function addFeatureBounty(uint256 _featureId) public payable {
        require(msg.value > 0, "Invalid bounty amount");
        featureBounties[_featureId] = featureBounties[_featureId].add(msg.value);
        _deposit(msg.sender, msg.value);
        emit FeatureBountyOffered(msg.sender, _featureId, msg.value, featureBounties[_featureId]);
    }

    /**
     * @dev Gets information about feature bounties
     * @param _featureIds list of feature ids
     * @param _bounties list of bounties in the same order of the ids requested
     */
    function getFeatureBounties(uint256[] memory _featureIds) public view returns (uint256[] memory _bounties) {
        uint[] memory res = new uint[](_featureIds.length);
        for (uint256 index = 0; index < _featureIds.length; index++) {
            res[index] = featureBounties[_featureIds[index]];
        }
        _bounties = res;
    }

    /**
     * @dev (admin) overrides the bounty amount offer for a feature.
     * @param _featureId feature id
     * @param _amount new amount
     */
    function overrideFeatureBounty(uint256 _featureId, uint256 _amount) public onlyOwner {
        featureBounties[_featureId] = _amount;
    }

    /**
     * @dev (admin) overrides an account plan
     * @param _account account address
     * @param _plan new plan id
     * @param _expiration new expiration (unix epoch in seconds)
     */
    function overrideAccountPlan(address _account, uint256 _plan, uint256 _expiration) public onlyOwner {
        _setAccountPlan(_account, _plan, _expiration);
    }

    /*
      Private APIs
     */
    function _purchase(address _account, uint256 _plan, uint256 _amount) private {
        uint256 newExpiration = getNewExpiration(_account, _plan, _amount);
        _setAccountPlan(_account, _plan, newExpiration);
    }

    function _setAccountPlan(address _account, uint256 _plan, uint256 _expiration) private {
        lastPurchasedPlan[_account] = _plan;
        lastPurchasedTimestamp[_account] = block.timestamp;
        planExpiration[_account] = _expiration;
        uint256 previousPlan = lastPurchasedPlan[_account];
        emit PlanChanged(_account, previousPlan, _plan, _expiration);
    }

    function _deposit(address _account, uint256 _amount) private
    {
        totalDeposited[_account] = totalDeposited[_account].add(_amount);
        
        // Split the received amount across all owner wallets
        uint256 remaining = _amount;
        uint256 index = 0;
        for (; index < devsQty - 1; index++) {
            address payable dest = devs[index];
            uint256 percentage = devsPercentage[dest];
            uint256 slice = _amount.mul(percentage).div(100);
            remaining -= slice;
            dest.transfer(slice);            
        }
        devs[index].transfer(remaining);

        // This should never happen, but just in case...
        // Avoid leaving any balance in the contract itself as it would be lost forever
        uint256 balance = address(this).balance;
        if (balance > 0 && devs[0] != address(0)) {
            devs[0].transfer(balance);
        }
    }
}