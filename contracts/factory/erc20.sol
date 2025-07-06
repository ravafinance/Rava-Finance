// SPDX-License-Identifier: MIT
// Website: https://rava.finance
// Twitter: https://x.com/RavaFinance
// Telegram https://t.me/RavaFinance

/*

▗▄▄▖  ▗▄▖ ▗▖  ▗▖ ▗▄▖ 
▐▌ ▐▌▐▌ ▐▌▐▌  ▐▌▐▌ ▐▌
▐▛▀▚▖▐▛▀▜▌▐▌  ▐▌▐▛▀▜▌
▐▌ ▐▌▐▌ ▐▌ ▝▚▞▘ ▐▌ ▐▌           

*/

pragma solidity ^0.8.30;
contract Token {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10**decimals;

    uint24 public pairFee;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public creator;
    address public owner = address(0);
    string public metadata;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
         string memory _symbol,
        address _creator,
        uint24 _pairFee,
        string memory _metadata
    ) {
        (name, symbol, creator, pairFee, metadata) = (_name, _symbol, _creator, _pairFee, _metadata);
        balanceOf[msg.sender] = totalSupply;

        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
    
    function setCreator(address _creator) external{  // for fee claim
        require(msg.sender == creator, "ERC20 RAVA: Not authorized");
        creator = _creator;
    }
}
