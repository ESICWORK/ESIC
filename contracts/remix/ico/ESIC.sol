pragma solidity ^0.4.23;


import 'github.com/OpenZeppelin/zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';

contract ESICToken is StandardToken {
    string public name = "Enterprise Service Improvement Chain";
    string public symbol = "ESIC";
    uint8 public decimals = 18;
    uint256 public INITIAL_SUPPLY = 10000000000000000000000000000;

    constructor() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = totalSupply_;
        emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
    }
}
