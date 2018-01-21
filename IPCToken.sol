pragma solidity ^0.4.18;

/**
 * @title SafeMath
 * @dev Math operations with safety checks
 */
contract SafeMath {
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b > 0);
        uint c = a / b;
        assert(a == b * c + a % b);
        return c;
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint c = a + b;
        assert(c>=a && c>=b);
        return c;
    }
}


/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
    uint256 public totalSupply;
    function balanceOf(address _owner) public constant returns (uint256 _balance);
    function allowance(address _owner, address _spender) public constant returns (uint256 _allowance);
    function transfer(address _to, uint256 _value) public returns (bool _succes);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool _succes);
    function approve(address _spender, uint256 _value) public returns (bool _succes);
    
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}


/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: 
 * https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, SafeMath {
    
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance; 
    
    function balanceOf(address _owner) public constant returns (uint256 _balance){
        return balanceOf[_owner];
    }
    
    function allowance(address _owner, address _spender) public constant returns (uint256 _remaining){
        return allowance[_owner][_spender];
    }
    
    /**
    * Fix for the ERC20 short address attack
    *
    * http://vessenes.com/the-erc20-short-address-attack-explained/
    */
    modifier onlyPayloadSize(uint size) {
        require(!(msg.data.length < size + 4));
        _;
    }
    
    /*
     * Internal transfer with security checks, 
     * only can be called by this contract
     */
    function _transfer(address _from, address _to, uint256 _value) internal {
            // Prevent transfer to 0x0 address.
            require(_to != 0x0);
            // Prevent transfer to this contract
            require(_to != address(this));
            // Check if the sender has enough and subtract from the sender by using sasafeSub
            balanceOf[_from] = safeSub(balanceOf[_from], _value);
            // check for overflows and add the same value to the recipient by using safeAdd
            balanceOf[_to] = safeAdd(balanceOf[_to], _value);
            Transfer(_from, _to, _value);
    }

    /**
     * @dev Send `_value` tokens to `_to` from your account
     * @param _to address The address which you want to transfer to
     * @param _value uint the amout of tokens to be transfered
     */
    function transfer(address _to, uint256 _value) onlyPayloadSize(2 * 32) public returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint the amout of tokens to be transfered
     */
    function transferFrom(address _from, address _to, uint256 _value) onlyPayloadSize(3 * 32) public returns (bool) {
        uint256 _allowance = allowance[_from][msg.sender];
        
        // Check (_value > _allowance) is already done in safeSub(_allowance, _value)
        allowance[_from][msg.sender] = safeSub(_allowance, _value);
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * @dev Aprove the passed address to spend the specified amount of tokens on beahlf of msg.sender.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        // To change the approve amount you first have to reduce the addresses`
        // allowance to zero by calling `approve(_spender, 0)` if it is not
        // already 0 to mitigate the race condition described here:
        // https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require((_value == 0) || (allowance[msg.sender][_spender] == 0));
        allowance[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }
}

/**
 * Upgrade agent interface inspired by Lunyr.
 *
 * Upgrade agent transfers tokens to a new contract.
 * Upgrade agent itself can be the token contract, or just a middle man contract doing the heavy lifting.
 */
contract UpgradeAgent {

    uint256 public originalSupply;

    /** Interface marker */
    function isUpgradeAgent() public pure returns (bool) {
        return true;
    }

    function upgradeFrom(address _from, uint256 _value) public;
}

/**
 * A token upgrade mechanism where users can opt-in amount of tokens to the next 
 * smart contract revision.
 *
 * First envisioned by Golem and Lunyr projects.
 */
contract UpgradeableToken is StandardToken {

    /**
     * Contract / person who can set the upgrade path. 
     * This can be the same as team multisig wallet, as what it is with its default value. 
     */
    address public upgradeMaster;

    /** The next contract where the tokens will be migrated. */
    UpgradeAgent public upgradeAgent;

    /** How many tokens we have upgraded by now. */
    uint256 public totalUpgraded;
    
    /**
     * Upgrade states.
     *
     * - NotAllowed: The child contract has not reached a condition where the upgrade can bgun
     * - WaitingForAgent: Token allows upgrade, but we don't have a new agent yet
     * - ReadyToUpgrade: The agent is set, but not a single token has been upgraded yet
     * - Upgrading: Upgrade agent is set and the balance holders can upgrade their tokens
     *
     */
    enum UpgradeState {Unknown, NotAllowed, WaitingForAgent, ReadyToUpgrade, Upgrading}

    /**
     * Somebody has upgraded some of his tokens.
     */
    event Upgrade(address indexed _from, address indexed _to, uint256 _value);

    /**
     * New upgrade agent available.
     */
    event UpgradeAgentSet(address agent);

    /**
     * Do not allow construction without upgrade master set.
     */
    function UpgradeableToken(address _upgradeMaster) public {
        upgradeMaster = _upgradeMaster;
    }

    /**
     * Allow the token holder to upgrade some of their tokens to a new contract.
     */
    function upgrade(uint256 value) public {

        UpgradeState state = getUpgradeState();
        // bad state not allowed
        require(state == UpgradeState.ReadyToUpgrade || state == UpgradeState.Upgrading);

        // Validate input value.
        require(value != 0);

        balanceOf[msg.sender] = safeSub(balanceOf[msg.sender], value);

        // Take tokens out from circulation
        totalSupply = safeSub(totalSupply, value);
        totalUpgraded = safeAdd(totalUpgraded, value);

        // Upgrade agent reissues the tokens
        upgradeAgent.upgradeFrom(msg.sender, value);
        Upgrade(msg.sender, upgradeAgent, value);
    }

    /**
     * Set an upgrade agent that handles
     */
    function setUpgradeAgent(address agent) external {

        require(canUpgrade());
        require(agent != 0x0);
        // Only a master can designate the next agent
        require(msg.sender == upgradeMaster);
        // Upgrade has already begun for an agent
        require(getUpgradeState() != UpgradeState.Upgrading);

        upgradeAgent = UpgradeAgent(agent);

        // Bad interface
        require(upgradeAgent.isUpgradeAgent());
        // Make sure that token supplies match in source and target
        require(upgradeAgent.originalSupply() == totalSupply);

        UpgradeAgentSet(upgradeAgent);
    }

    /**
     * Get the state of the token upgrade.
     */
    function getUpgradeState() public constant returns (UpgradeState) {
        if(!canUpgrade()) return UpgradeState.NotAllowed;
        else if(address(upgradeAgent) == 0x00) return UpgradeState.WaitingForAgent;
        else if(totalUpgraded == 0) return UpgradeState.ReadyToUpgrade;
        else return UpgradeState.Upgrading;
    }

    /**
     * Change the upgrade master.
     *
     * This allows us to set a new owner for the upgrade mechanism.
     */
    function setUpgradeMaster(address master) public {
        require(master != 0x0);
        require(msg.sender == upgradeMaster);
        upgradeMaster = master;
    }

    /**
     * Child contract can enable to provide the condition when the upgrade can begun.
     */
    function canUpgrade() public pure returns (bool) {
        return true;
    }
}


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;


    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    function Ownable() public {
        owner = msg.sender;
    }


    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0));
        owner = newOwner;
    }
}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;


    /**
     * @dev modifier to allow actions only when the contract IS paused
     */
    modifier whenNotPaused {
        require(!paused);
        _;
    }

    /**
     * @dev modifier to allow actions only when the contract IS NOT paused
     */
    modifier whenPaused {
        require(paused);
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() onlyOwner whenNotPaused public returns (bool) {
        paused = true;
        Pause();
        return true;
  }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() onlyOwner whenPaused public returns (bool) {
        paused = false;
        Unpause();
        return true;
    }
}

/**
 * Pausable token
 *
 * Simple ERC20 Token example, with pausable token creation
 */
contract PausableToken is StandardToken, Pausable {
    function transfer(address _to, uint256 _value) whenNotPaused public returns (bool) {
        super.transfer(_to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) whenNotPaused public returns (bool) {
        super.transferFrom(_from, _to, _value);
        return true;
    }
}


/**
 * @title IPCToken
 * @dev IPC Token contract
 */
contract IPCToken is PausableToken, UpgradeableToken {
    
    // prevents sending ether to this contract
    function () public {
        bool etherAllowed = false;
        require(etherAllowed);
    }

    // Public variables of the token
    string public name = "Test";
    string public symbol = "TestToken";
    // Total supply of 44 mio with 12 decimals
    uint8 public decimals = 12;
    uint256 public totalSupply = 440000000 * (10 ** uint256(decimals));
    // Distributions of the total supply
    uint256 public cr = 264000000 * (10 ** uint256(decimals)); // 264 mio for crowdsale
    uint256 public dev = 66000000 * (10 ** uint256(decimals)); // 66 mio for advisors and partners
    uint256 public rew = 110000000 * (10 ** uint256(decimals)); // 110 mio reserved for reward

    event UpdatedTokenInformation(string newName, string newSymbol);
   
    /**
     * Constructor of ipc token
     * 
     * @param addressOfCrBen beneficiary of crowdsale
     * @param addressOfDev token holder for development 
     * @param addressOfRew reserve remaining amount of ipc for reward program at this address
     */
    function IPCToken (
        address addressOfCrBen, 
        address addressOfDev,
        address addressOfRew
        ) public UpgradeableToken(msg.sender) {
        // Assign the initial tokens to the addresses
        balanceOf[addressOfCrBen] = cr;
        balanceOf[addressOfDev] = dev;
        balanceOf[addressOfRew] = rew;
    }
    
    /**
     * Owner can update token information here
     * 
     * @param _name new token name
     * @param _symbol new token symbol
     */
    function setTokenInformation(string _name, string _symbol) onlyOwner public {
        name = _name;
        symbol = _symbol;

        UpdatedTokenInformation(name, symbol);
    }
}