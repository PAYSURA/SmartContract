pragma solidity ^0.4.18;

/**
 * @title SafeMath
 * @dev Math operations with safety checks
 */
contract SafeMath {
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b > 0);
        uint256 c = a / b;
        assert(a == b * c + a % b);
        return c;
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a && c >= b);
        return c;
    }
}


/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20Basic {
    uint256 public totalSupply;
    uint8 public decimals;
    function balanceOf(address _owner) public constant returns (uint256 _balance);
    function transfer(address _to, uint256 _value) public returns (bool _succes);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
}



/**
 * @title Crowdsale
 * @dev Crowdsale contract 
 */
contract Crowdsale is SafeMath {

    // The token being sold
    ERC20Basic public token;
    
    // address where funds are collected
    address public crowdsaleAgent;
    
    // amount of raised money in wei
    uint256 public weiRaised;
    
    // ether rate in USD-Cent
    uint etherRateInUSDCent;
    
    // minimum amount of ether to participate in ICO
    uint256 minimumEtherAmount = 0.2 ether;

    // start and end timestamps where investments are allowed (both inclusive)
    // + deadlines within bonus program
    uint256 public startTime = 1520082000;     //(GMT): Saturday, 3. March 2018 13:00:00
    uint256 public deadlineOne = 1520168400;   //(GMT): Sunday, 4. March 2018 13:00:00
    uint256 public deadlineTwo = 1520427600;   //(GMT): Wednesday, 7. March 2018 13:00:00
    uint256 public deadlineThree = 1520773200; //(GMT): Sunday, 11. March 2018 13:00:00
    uint256 public endTime = 1522674000;       //(GMT): Monday, 2. April 2018 13:00:00 
    
    // token price in USD Cent during crowdsale
    uint public bonusOne = 12; 
    uint public bonusTwo = 14;
    uint public bonusThree = 16;
    uint public finalSale = 18;

    // arrays with all distributed token balance during Crowdsale
    mapping(address => uint256) public distribution;
    
    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    modifier onlyCrowdsaleAgent {
        require(msg.sender == crowdsaleAgent);
        _;
    }    
    
    function Crowdsale(uint _etherRateInUSDCent, address _crowdsaleAgent, address _token) public {
        require(_etherRateInUSDCent > 0);
        require(_crowdsaleAgent != address(0));
        require(_token != address(0));

        etherRateInUSDCent = _etherRateInUSDCent;
        crowdsaleAgent = _crowdsaleAgent;
        token = ERC20Basic(_token);
    }

    // fallback function can be used to buy tokens
    function () public payable {
        buyTokens(msg.sender);
    }

    // token purchase function
    function buyTokens(address beneficiary) public payable {
        require(beneficiary != address(0));
        require(validPurchase());
        uint256 weiAmount = msg.value;
        // calculate token amount to be transferred to beneficiary
        uint256 tokens = calcTokenAmount(weiAmount);
        // update state
        weiRaised = safeAdd(weiRaised, weiAmount);
        distribution[beneficiary] = safeAdd(distribution[beneficiary], tokens);
        token.transfer(beneficiary, tokens);
        TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);
        forwardFunds();
    }

    // return true if crowdsale event has ended
    function hasEnded() public view returns (bool) {
        return now > endTime;
    }
    
    // set crowdsale begin
    function setStartTime(uint256 _startTime) onlyCrowdsaleAgent public returns (bool) {
        startTime = _startTime;
        return true;
    }
    
    // set crowdsale end
    function setEndTime(uint256 _endTime) onlyCrowdsaleAgent public returns (bool) {
        endTime = _endTime;
        return true;
    }

    // set crowdsale wallet where funds are collected
    function setCrowdsaleAgent(address _crowdsaleAgent) onlyCrowdsaleAgent public returns (bool) {
        crowdsaleAgent = _crowdsaleAgent;
        return true;
    }
    
    // set exchange rate of ether
    function setEtherRate(uint _etherRateInUSDCent) onlyCrowdsaleAgent public returns (bool) {
        etherRateInUSDCent = _etherRateInUSDCent;
        return true;
    }
    
    // set new final token rate in USD-Cent
    function setFinalRate(uint _finalSaleInUSDCent) onlyCrowdsaleAgent public returns (bool) {
        finalSale = _finalSaleInUSDCent;
        return true;
    }
    
    // set new minumum amount of Wei to participate in ICO
    function setMinimumEtherAmount(uint256 _minimumEtherAmountInWei) onlyCrowdsaleAgent public returns (bool) {
        minimumEtherAmount = _minimumEtherAmountInWei;
        return true;
    }
    
    // withdraw remaining token amount after crowdsale has ended
    function withdrawToken() onlyCrowdsaleAgent public returns (bool) {
        uint256 remainingToken = token.balanceOf(this);
        require(hasEnded() && remainingToken > 0);
        token.transfer(crowdsaleAgent, remainingToken);
        return true;
    }

    // Calculate the token amount from the donated ETH onsidering the bonus system.
    function calcTokenAmount(uint256 weiAmount) internal view returns (uint256) {
        uint256 bonus;
        if (now >= startTime && now < deadlineOne) {
            bonus = bonusOne; 
        } else if (now >= deadlineOne && now < deadlineTwo) {
            bonus = bonusTwo;
        } else if (now >= deadlineTwo && now < deadlineThree) {
            bonus = bonusThree;
        } else if (now >= deadlineThree && now <= endTime) {
        	bonus = finalSale;
        }
        uint256 tokens = safeDiv(safeMul(weiAmount, etherRateInUSDCent), bonus);
        uint8 decimalCut = 18 > token.decimals() ? 18-token.decimals() : 1;
        return safeDiv(tokens, 10**uint256(decimalCut));
    }

    // forward ether to the fund collection wallet
    function forwardFunds() internal {
        crowdsaleAgent.transfer(msg.value);
    }

    // return true if the transaction can buy tokens
    function validPurchase() internal view returns (bool) {
        bool withinPeriod = now >= startTime && now <= endTime;
        bool isMinimumAmount = msg.value >= minimumEtherAmount;
        bool hasTokenBalance = token.balanceOf(this) > 0;
        return withinPeriod && isMinimumAmount && hasTokenBalance;
    }
     
    // selfdestruct crowdsale contract only after crowdsale has ended
    function killContract() onlyCrowdsaleAgent public {
        require(hasEnded() && token.balanceOf(this) == 0);
        selfdestruct(crowdsaleAgent);
    }
}
