pragma solidity ^0.5.0;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}


contract DFL8 {
    uint PRECISION            = 1e18;
    string public name        = "Deflationary Ether";
    string public symbol      = "DFL8";
    uint8  public decimals    = 18;
    uint   public burnPercent = 5;  // 1000 precision. 5 = 0.5%, 10 = 1%, etc. 
    uint   public totalSupply;
    uint   public burnedTokens;
    address public whitelistManager;
    
    bool trigger = false;
    

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad, uint amt);
    event  Withdrawal(address indexed src, uint wad, uint amt);
    
    event  AddSwapWhitelist(address indexed addr);
    event  AddUnswapWhitelist(address indexed addr);
    event  AddTransferWhitelist(address indexed addr);

    event  DelSwapWhitelist(address indexed addr);
    event  DelUnswapWhitelist(address indexed addr);
    event  DelTransferWhitelist(address indexed addr);

    mapping (address => uint)                       public balanceOf;
    mapping (address => mapping (address => uint))  public allowance;
    mapping (address => bool)                       public wrapWhitelist;
    mapping (address => bool)                       public unwrapWhitelist;
    mapping (address => bool)                       public transferWhitelist;

     
    // Modifiers
    modifier onlyWhitelistManager {
        require(msg.sender == whitelistManager, "Not Whitelist Manager");
        _;
    }

    constructor() public {
        whitelistManager = msg.sender;
    }

    function() external payable {
        deposit();
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    function getTokenBalance() public view returns (uint256) {
        return totalSupply;
    }
    
    function getTokenPrice() public view returns (uint256) {
        return getPrice();
    }
    
    function getPrice() internal view returns (uint256) {
        uint _price;
        uint _contractBalance;
        
        // msg.value is added to contract before code execution, we are looking for previous price.
        if(msg.value > 0) {
            _contractBalance = address(this).balance - msg.value;
        } else {
            _contractBalance = address(this).balance;
        }
        
        // Give DFL8 price of 1 ETH if contraxt empty. 
        if(_contractBalance > 0 && totalSupply > 0) {
            uint _bigPrice = SafeMath.mul(_contractBalance, 1e18);
            uint _tmpPrice = SafeMath.div(_bigPrice, totalSupply);
            uint _newPrice = SafeMath.mul(_tmpPrice, 1e18);
            _price = SafeMath.div(_newPrice, 1e18);
        } else {
            _price = 1 ether;
        }
        return _price;
    }

    function getBurn(uint _amount) public view returns (uint256) {
        return SafeMath.div(SafeMath.mul(_amount, burnPercent), 1000);
    }

    function getTokensForEth(uint _amount) public view returns (uint256) {
        uint _tokenAmount = SafeMath.mul(_amount, 1e18);
        uint _tokenCorrectedAmount = SafeMath.div(_tokenAmount, getPrice());
        return _tokenCorrectedAmount;
    }

    function getEthForTokens(uint _amount) public view returns (uint256) {
        uint _ethAmount = SafeMath.mul(_amount, getPrice());
        uint _ethCorrectedAmount = SafeMath.div(_ethAmount, 1e18);   
        return _ethCorrectedAmount;
    }

    // Deposit ETH
    function deposit() public payable {
        uint _tokenAmount;
        uint _burnAmount;
        uint _ethAmount;
        
        if(wrapWhitelist[msg.sender]) {
            _tokenAmount = getTokensForEth(msg.value);
        } else {
            _burnAmount  = getBurn(msg.value);
            _ethAmount   = msg.value - _burnAmount;
            _tokenAmount = getTokensForEth(_ethAmount);
            
            burnedTokens += _burnAmount;
        } 

        balanceOf[msg.sender] += _tokenAmount;
        totalSupply += _tokenAmount;
        emit Deposit(msg.sender, _tokenAmount, msg.value);
    }
    
    // Withdraw DFL8 (to avoid changes in price, DFL8 holding are stable)
    function withdraw(uint _amount) public {
        require(balanceOf[msg.sender] >= _amount, "Insufficient DFL8 Tokens");

        uint _tokenAmount;
        uint _etherAmount;
        uint _burnAmount;
        
        // Dont burn if on whitelist, or if last person in contract.
        if(unwrapWhitelist[msg.sender] || _amount >= totalSupply) {
            _tokenAmount = _amount;
        } else {
            _burnAmount = getBurn(_amount);
            _tokenAmount = _amount - _burnAmount;
            
            burnedTokens += _burnAmount;
        }

        _etherAmount = getEthForTokens(_tokenAmount);

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;

        // Get rid of dust to allow price to reset back to 1 ETH if contract empties
        if(totalSupply <= 0) { 
            _etherAmount = address(this).balance;
        }

        msg.sender.transfer(_etherAmount);

        emit Withdrawal(msg.sender, _tokenAmount, _etherAmount);
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad, "Insufficient Funds");

        uint _transferAmount;
        uint _burnAmount;
        
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        if(transferWhitelist[msg.sender]) {
            _transferAmount = wad;
        } else {
            _burnAmount = getBurn(wad);
            burnedTokens += _burnAmount;
            _transferAmount = wad - _burnAmount;
        } 


        balanceOf[src] -= wad;
        balanceOf[dst] += _transferAmount;
        burnedTokens += _burnAmount;

        emit Transfer(src, dst, wad);

        return true;
    }

    function addUnswapWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        unwrapWhitelist[_addr] = true;
        emit AddUnswapWhitelist(_addr);
        return true;
    }

    function addSwapWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        wrapWhitelist[_addr] = true;
        emit AddSwapWhitelist(_addr);
        return true;
    }

    function addTransferWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        transferWhitelist[_addr] = true;
        emit AddTransferWhitelist(_addr);
        return true;
    }

    function delUnswapWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        unwrapWhitelist[_addr] = false;
        emit DelSwapWhitelist(_addr);
        return true;
    }

    function delSwapWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        wrapWhitelist[_addr] = false;
        emit DelSwapWhitelist(_addr);
        return true;
    }

    function delTransferWhitelist(address _addr) onlyWhitelistManager public returns (bool) {
        transferWhitelist[_addr] = false;
        emit DelTransferWhitelist(_addr);
        return true;
    }
}

