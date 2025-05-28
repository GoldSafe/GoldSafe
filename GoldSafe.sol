
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ERC-20 Interface Definition
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Main contract for GoldSafe Token with DAO governance and full vesting
contract GoldSafe is IERC20 {
    string public name = "GoldSafe";
    string public symbol = "GS";
    uint8 public decimals = 8;
    uint256 public override totalSupply;

    address public owner;
    bool public paused;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => bool) public frozenAccounts;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 amountClaimed;
        uint256 startTime;
        uint256 initialUnlock;
        uint256 monthlyRelease;
        uint256 monthsDuration;
    }

    struct Proposal {
        string description;
        uint256 voteYes;
        uint256 voteNo;
        uint256 deadline;
        bool executed;
        mapping(address => bool) voted;
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    address public marketingWallet = 0x2222222222222222222222222222222222222222;
    address public communityWallet = 0x3333333333333333333333333333333333333333;
    address public liquidityWallet = 0x4444444444444444444444444444444444444444;
    address public reserveWallet = 0x5555555555555555555555555555555555555555;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier notPaused() {
        require(!paused, "Transfers are paused");
        _;
    }

    modifier notFrozen(address account) {
        require(!frozenAccounts[account], "Account is frozen");
        _;
    }

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, string description, uint256 deadline);
    event Voted(address indexed voter, uint256 proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, bool approved);

    constructor() {
        owner = msg.sender;
        uint256 base = 10 ** uint256(decimals);

        // Team vesting schedule (owner)
        uint256 teamTotal = 6_000_000 * base;
        vestingSchedules[owner] = VestingSchedule({
            totalAmount: teamTotal,
            amountClaimed: 600_000 * base,
            startTime: block.timestamp,
            initialUnlock: 600_000 * base,
            monthlyRelease: 600_000 * base,
            monthsDuration: 9
        });

        // Strategic investor vesting schedule
        address strategicInvestor = 0x9999999999999999999999999999999999999999;
        vestingSchedules[strategicInvestor] = VestingSchedule({
            totalAmount: 5_000_000 * base,
            amountClaimed: 0,
            startTime: block.timestamp + 60 days,
            initialUnlock: 1_000_000 * base,
            monthlyRelease: 500_000 * base,
            monthsDuration: 8
        });

        uint256 marketingAmount = 3_000_000 * base;
        uint256 communityAmount = 2_000_000 * base;
        uint256 liquidityAmount = 3_000_000 * base;
        uint256 reserveAmount = 6_000_000 * base;

        totalSupply = teamTotal + marketingAmount + communityAmount + liquidityAmount + reserveAmount;

        balanceOf[marketingWallet] = marketingAmount;
        balanceOf[communityWallet] = communityAmount;
        balanceOf[liquidityWallet] = liquidityAmount;
        balanceOf[reserveWallet] = reserveAmount;
        balanceOf[owner] = 600_000 * base;

        emit Transfer(address(0), owner, 600_000 * base);
        emit Transfer(address(0), marketingWallet, marketingAmount);
        emit Transfer(address(0), communityWallet, communityAmount);
        emit Transfer(address(0), liquidityWallet, liquidityAmount);
        emit Transfer(address(0), reserveWallet, reserveAmount);
    }

    // Claims vested tokens for sender (team or strategic)
    function claimTokens() external {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(block.timestamp >= schedule.startTime, "Vesting not started");

        uint256 monthsPassed = (block.timestamp - schedule.startTime) / 30 days;
        if (monthsPassed > schedule.monthsDuration) {
            monthsPassed = schedule.monthsDuration;
        }

        uint256 totalUnlocked = schedule.initialUnlock + (monthsPassed * schedule.monthlyRelease);
        if (totalUnlocked > schedule.totalAmount) {
            totalUnlocked = schedule.totalAmount;
        }

        require(totalUnlocked > schedule.amountClaimed, "Nothing to claim");
        uint256 claimable = totalUnlocked - schedule.amountClaimed;
        schedule.amountClaimed = totalUnlocked;
        balanceOf[msg.sender] += claimable;

        emit Transfer(address(0), msg.sender, claimable);
        emit TokensClaimed(msg.sender, claimable);
    }

    function createProposal(string calldata description) external returns (uint256) {
        proposals[proposalCount].description = description;
        proposals[proposalCount].deadline = block.timestamp + 3 days;
        emit ProposalCreated(proposalCount, description, proposals[proposalCount].deadline);
        return proposalCount++;
    }

    function voteOnProposal(uint256 proposalId, bool support) external {
        Proposal storage prop = proposals[proposalId];
        require(block.timestamp < prop.deadline, "Voting ended");
        require(!prop.voted[msg.sender], "Already voted");
        uint256 weight = balanceOf[msg.sender];
        require(weight > 0, "No tokens to vote");

        if (support) {
            prop.voteYes += weight;
        } else {
            prop.voteNo += weight;
        }
        prop.voted[msg.sender] = true;
        emit Voted(msg.sender, proposalId, support, weight);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage prop = proposals[proposalId];
        require(block.timestamp >= prop.deadline, "Voting still active");
        require(!prop.executed, "Already executed");

        prop.executed = true;
        bool approved = prop.voteYes > prop.voteNo;
        emit ProposalExecuted(proposalId, approved);
    }

    function transfer(address to, uint256 amount) external override notPaused notFrozen(msg.sender) notFrozen(to) returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override notPaused notFrozen(msg.sender) notFrozen(spender) returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override notPaused notFrozen(from) notFrozen(to) returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function freezeAccount(address account) external onlyOwner {
        frozenAccounts[account] = true;
    }

    function unfreezeAccount(address account) external onlyOwner {
        frozenAccounts[account] = false;
    }

    function burn(uint256 amount) external notPaused notFrozen(msg.sender) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }
}
