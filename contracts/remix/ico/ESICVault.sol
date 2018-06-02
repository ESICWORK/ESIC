pragma solidity ^0.4.23;


import 'github.com/OpenZeppelin/zeppelin-solidity/contracts/ownership/Ownable.sol';
import './ESIC.sol';

contract ESICVault is Ownable {
    using SafeMath for uint256;

    //Wallet Addresses for allocation
    address public teamReserveWallet = 0x9b0a078A5A8d5f96a810C73E7ED5b63c93729D16;
    address public firstReserveWallet = 0xbFFE5Cffc49dB70c5feed6dCB442D4f22dA5B429;
    address public secondReserveWallet = 0x4CA66d047e74C6772700829bC00f1e5D47b4BAb8;

    //Token Allocations
    uint256 public teamReserveAllocation = 4 * (10 ** 8) * (10 ** 18);
    uint256 public firstReserveAllocation = 2 * (10 ** 8) * (10 ** 18);
    uint256 public secondReserveAllocation = 3 * (10 ** 8) * (10 ** 18);

    //Total Token Allocations
    uint256 public totalAllocation = 9 * (10 ** 8) * (10 ** 18);

    uint256 public teamTimeLock = 60 minutes; // 2 * 365 days;
    uint256 public teamVestingStages = 6;
    uint256 public firstReserveTimeLock = 30 minutes; // 2 * 365 days;
    uint256 public secondReserveTimeLock = 40 minutes; // 3 * 365 days;

    /** Reserve allocations */
    mapping(address => uint256) public allocations;

    /** When timeLocks are over (UNIX Timestamp)  */
    mapping(address => uint256) public timeLocks;

    /** How many tokens each reserve wallet has claimed */
    mapping(address => uint256) public claimed;

    /** When this vault was locked (UNIX Timestamp)*/
    uint256 public lockedAt = 0;

    ESICToken public token;

    /** Allocated reserve tokens */
    event Allocated(address wallet, uint256 value);

    /** Distributed reserved tokens */
    event Distributed(address wallet, uint256 value);

    /** Tokens have been locked */
    event Locked(uint256 lockTime);

    //Any of the three reserve wallets
    modifier onlyReserveWallets {
        require(allocations[msg.sender] > 0);
        _;
    }

    //Only ESIC team reserve wallet
    modifier onlyTeamReserve {
        require(msg.sender == teamReserveWallet);
        require(allocations[msg.sender] > 0);
        _;
    }

    //Only first and second token reserve wallets
    modifier onlyTokenReserve {
        require(msg.sender == firstReserveWallet || msg.sender == secondReserveWallet);
        require(allocations[msg.sender] > 0);
        _;
    }

    //Has not been locked yet
    modifier notLocked {
        require(lockedAt == 0);
        _;
    }

    modifier locked {
        require(lockedAt > 0);
        _;
    }

    //Token allocations have not been set
    modifier notAllocated {
        require(allocations[teamReserveWallet] == 0);
        require(allocations[firstReserveWallet] == 0);
        require(allocations[secondReserveWallet] == 0);
        _;
    }

    constructor(ERC20 _token) public {

        owner = msg.sender;
        token = ESICToken(_token);

    }

    function allocate() public notLocked notAllocated onlyOwner {

        //Makes sure Token Contract has the exact number of tokens
        require(token.balanceOf(address(this)) == totalAllocation);

        allocations[teamReserveWallet] = teamReserveAllocation;
        allocations[firstReserveWallet] = firstReserveAllocation;
        allocations[secondReserveWallet] = secondReserveAllocation;

        emit Allocated(teamReserveWallet, teamReserveAllocation);
        emit Allocated(firstReserveWallet, firstReserveAllocation);
        emit Allocated(secondReserveWallet, secondReserveAllocation);

        lock();
    }

    //Lock the vault for the three wallets
    function lock() internal notLocked onlyOwner {

        lockedAt = block.timestamp;

        timeLocks[teamReserveWallet] = lockedAt.add(teamTimeLock);
        timeLocks[firstReserveWallet] = lockedAt.add(firstReserveTimeLock);
        timeLocks[secondReserveWallet] = lockedAt.add(secondReserveTimeLock);

        emit Locked(lockedAt);
    }

    //In the case locking failed, then allow the owner to reclaim the tokens on the contract.
    //Recover Tokens in case incorrect amount was sent to contract.
    function recoverFailedLock() external notLocked notAllocated onlyOwner {

        // Transfer all tokens on this contract back to the owner
        require(token.transfer(owner, token.balanceOf(address(this))));
    }

    // Total number of tokens currently in the vault
    function getTotalBalance() public view returns (uint256 tokensCurrentlyInVault) {

        return token.balanceOf(address(this));

    }

    // Number of tokens that are still locked
    function getLockedBalance() public view onlyReserveWallets returns (uint256 tokensLocked) {

        return allocations[msg.sender].sub(claimed[msg.sender]);

    }

    //Claim tokens for first/second reserve wallets
    function claimTokenReserve() onlyTokenReserve locked public {

        address reserveWallet = msg.sender;

        // Can't claim before Lock ends
        require(block.timestamp > timeLocks[reserveWallet]);

        // Must Only claim once
        require(claimed[reserveWallet] == 0);

        uint256 amount = allocations[reserveWallet];

        claimed[reserveWallet] = amount;

        require(token.transfer(reserveWallet, amount));

        emit Distributed(reserveWallet, amount);
    }

    //Claim tokens for ESIC team reserve wallet
    function claimTeamReserve() onlyTeamReserve locked public {

        uint256 vestingStage = teamVestingStage();

        //Amount of tokens the team should have at this vesting stage
        uint256 totalUnlocked = vestingStage.mul(allocations[teamReserveWallet]).div(teamVestingStages);

        require(totalUnlocked <= allocations[teamReserveWallet]);

        //Previously claimed tokens must be less than what is unlocked
        require(claimed[teamReserveWallet] < totalUnlocked);

        uint256 payment = totalUnlocked.sub(claimed[teamReserveWallet]);

        claimed[teamReserveWallet] = totalUnlocked;

        require(token.transfer(teamReserveWallet, payment));

        emit Distributed(teamReserveWallet, payment);
    }

    //Current Vesting stage for ESIC team
    function teamVestingStage() public view onlyTeamReserve returns(uint256){

        // Every 3 months
        uint256 vestingMonths = teamTimeLock.div(teamVestingStages);

        uint256 stage = (block.timestamp.sub(lockedAt)).div(vestingMonths);

        //Ensures team vesting stage doesn't go past teamVestingStages
        if(stage > teamVestingStages){
            stage = teamVestingStages;
        }

        return stage;

    }

    // Checks if msg.sender can collect tokens
    function canCollect() public view onlyReserveWallets returns(bool) {

        return block.timestamp > timeLocks[msg.sender] && claimed[msg.sender] == 0;

    }

}
