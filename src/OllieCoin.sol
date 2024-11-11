// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @title OllieCoin
 * @dev Implementation of the OllieCoin token with reward distribution functionality
 * and reward delegation capabilities.
 */
contract OllieCoin is ERC20, Ownable {
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;
    using SafeCast for uint48;

    // Constant for day duration in seconds
    uint256 private constant SECONDS_PER_DAY = 86400;
    // Used for the first distribution
    uint256 private immutable INITIAL_TIMESTAMP;

    // Mapping of user balances to their checkpoints
    mapping(address => Checkpoints.Trace208) private _balanceCheckpoints;
    // Mapping for reward weight delegation
    mapping(address => Checkpoints.Trace208) private _rewardWeightCheckpoints;
    // Mapping of delegators to their chosen delegatee
    mapping(address => address) private _rewardDelegatee;
    // Mapping for reward weight preservation settings
    mapping(address => mapping(address => bool)) private _preserveRewardWeight;

    /**
     * @dev Struct representing a reward distribution period
     */
    struct Distribution {
        ERC20 token;
        uint48 startTime;
        uint48 endTime;
        uint256 rewardsPerTokenPerDay;
    }

    // Events
    event DistributionCreated(address indexed token, uint256 rewardsPerTokenPerDay, uint48 startTime, uint48 endTime);
    event RewardsClaimed(address indexed account, address indexed token, uint256 amount);
    event RewardDelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event RewardWeightChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event RewardWeightPreservationSet(address indexed owner, address indexed spender, bool preserved);

    // Array to store all distributions
    Distribution[] private _distributions;

    // Track last claimed distribution for each user
    mapping(address => uint256) private _lastClaimedDistribution;

    constructor(string memory name, string memory symbol, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {
        INITIAL_TIMESTAMP = block.timestamp;
    }

    /**
     * @dev Delegate reward weight to another address
     * @param delegatee The address to delegate the reward weight to
     */
    function delegateRewards(address delegatee) public {
        _delegateRewards(_msgSender(), delegatee);
    }

    /**
     * @dev Allows users to claim their accumulated rewards from all unclaimed distribution periods
     *
     * The claiming process:
     * 1. Iterates through all unclaimed distribution periods
     * 2. For each period, calculates rewards based on historical balance
     * 3. Groups rewards by token type (handles multiple reward tokens)
     * 4. Transfers accumulated rewards when token type changes or at end
     *
     * Key features:
     * - Supports multiple reward token types
     * - Uses historical balances for accurate reward calculation
     * - Batches transfers for gas efficiency
     * - Maintains claim status to prevent double claiming
     */
    function claim() external {
        address account = _msgSender();
        uint256 lastClaimedId = _lastClaimedDistribution[account];

        uint256 totalRewards = 0;
        ERC20 currentToken;

        for (uint256 i = lastClaimedId; i < _distributions.length; i++) {
            Distribution storage dist = _distributions[i];

            // Skip invalid distributions
            if (dist.endTime == 0) continue;

            // Calculate rewards for each day in the distribution period
            for (uint48 day = dist.startTime; day < dist.endTime; day += uint48(SECONDS_PER_DAY)) {
                // Get historical balance at the start of this day
                uint256 balance = getPastBalance(account, day);
                if (balance == 0) continue;

                // Add rewards for this day using precision scaling
                uint256 dailyReward = balance * dist.rewardsPerTokenPerDay / 1e18;
                totalRewards += dailyReward;
            }

            // Handle token type change and transfers
            if (currentToken != dist.token && currentToken != ERC20(address(0))) {
                // Transfer rewards to the account (using call to avoid tokens poisoning that would affect the future distributions)
                (bool success,) =
                    address(currentToken).call(abi.encodeWithSelector(IERC20.transfer.selector, account, totalRewards));
                if (success) {
                    emit RewardsClaimed(account, address(currentToken), totalRewards);
                }
                totalRewards = 0;
            }

            currentToken = dist.token;
        }

        // Update last claimed distribution
        _lastClaimedDistribution[account] = _distributions.length;

        // Transfer any remaining rewards
        if (totalRewards > 0 && currentToken != ERC20(address(0))) {
            // Transfer rewards to the account (using call to avoid tokens poisoning that would affect the future distributions)
            (bool success,) =
                address(currentToken).call(abi.encodeWithSelector(IERC20.transfer.selector, account, totalRewards));
            if (success) {
                emit RewardsClaimed(account, address(currentToken), totalRewards);
            }
        }
    }

    /**
     * @dev Initiates a new reward distribution period
     * @param token The ERC20 token to distribute as rewards
     * @param amount The total amount of tokens to distribute
     *
     * The distribution process:
     * 1. Transfers reward tokens from owner to contract
     * 2. Calculates per-token reward rate
     * 3. Determines distribution period (from last distribution end to current time)
     * 4. Records distribution details for future claims
     */
    function distribute(ERC20 token, uint256 amount) external onlyOwner {
        // Transfer tokens from distributor to contract
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Get current state for distribution period
        uint48 currentTime = uint48(block.timestamp);

        // Determine start time for distribution period
        uint48 startTime;
        if (_distributions.length > 0) {
            Distribution storage lastDist = _distributions[_distributions.length - 1];
            startTime = lastDist.endTime;
        } else {
            startTime = uint48(INITIAL_TIMESTAMP);
        }

        // Calculate days in distribution period using the correct start time
        uint256 daysInPeriod = (currentTime - startTime) / SECONDS_PER_DAY;

        // Calculate daily rewards per token with precision scaling
        uint256 rewardsPerTokenPerDay = (amount * 1e18) / (totalSupply() * daysInPeriod);

        // Record new distribution period
        _distributions.push(
            Distribution({
                token: token,
                rewardsPerTokenPerDay: rewardsPerTokenPerDay,
                startTime: startTime,
                endTime: currentTime
            })
        );

        emit DistributionCreated(address(token), rewardsPerTokenPerDay, startTime, currentTime);
    }

    /**
     * @dev Mint function for testing purposes
     * @param to The address to mint the tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);

        _delegateRewards(to, to);
    }

    /**
     * @dev Transfers tokens without reward weight changes
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transferWithoutRewardDelegation(address to, uint256 amount) external {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        super._update(msg.sender, to, amount);
    }

    /**
     * @dev Sets whether a spender should preserve the owner's reward weight during transfers
     * This is separate from the standard approve mechanism
     * @param spender Address that will be able to initiate transfer that won't impact the reward Weight
     * @param preserve If true, transfers from this spender won't affect reward weight
     */
    function setRewardWeightPreservation(address spender, bool preserve) external {
        require(spender != address(0), "Invalid spender address");
        _preserveRewardWeight[msg.sender][spender] = preserve;
        emit RewardWeightPreservationSet(msg.sender, spender, preserve);
    }

    /**
     * @dev Gets the balance at a specific timestamp, considering delegations
     * @param account The address to get the balance for
     * @param timestamp The timestamp to get the balance at
     * @return The balance at the specified timestamp
     */
    function getPastBalance(address account, uint48 timestamp) public view returns (uint256) {
        return getPastRewardWeight(account, timestamp);
    }

    /**
     * @dev Returns the current reward Weight for an account
     * @param account The address to get the reward weight for
     * @return The reward weight for the specified address
     */
    function getRewardWeight(address account) public view returns (uint256) {
        return _rewardWeightCheckpoints[account].latest();
    }

    /**
     * @dev Returns the reward Weight of an account at a specific timestamp
     * @param account The address to get the reward weight for
     * @param timestamp The timestamp to get the reward weight at
     * @return The reward weight for the specified address at the specified timestamp
     */
    function getPastRewardWeight(address account, uint48 timestamp) public view returns (uint256) {
        return _rewardWeightCheckpoints[account].upperLookupRecent(timestamp);
    }

    /**
     * @dev Gets pending rewards for an account
     * @param account The address to get the pending rewards for
     * @return The pending rewards for the specified address
     */
    function getPendingRewards(address account) external view returns (uint256) {
        uint256 lastClaimedId = _lastClaimedDistribution[account];
        uint256 totalRewards = 0;

        for (uint256 i = lastClaimedId; i < _distributions.length; i++) {
            Distribution memory dist = _distributions[i];

            // Skip invalid distributions
            if (dist.endTime == 0) continue;

            // Calculate rewards for each day in the distribution period
            for (uint48 day = dist.startTime; day < dist.endTime; day += uint48(SECONDS_PER_DAY)) {
                // Get historical balance at the start of this day
                uint256 balance = getPastBalance(account, day);
                if (balance == 0) continue;

                // Add rewards for this day using precision scaling
                uint256 dailyReward = (balance * dist.rewardsPerTokenPerDay) / 1e18;
                totalRewards += dailyReward;
            }
        }

        return totalRewards;
    }

    /**
     * @dev Checks if a spender is set to preserve reward weight for an owner
     * @param owner Address of the token owner
     * @param spender Address of the spender
     * @return bool True if spender preserves reward weight
     */
    function hasRewardWeightPreservation(address owner, address spender) external view returns (bool) {
        return _preserveRewardWeight[owner][spender];
    }

    /**
     * @dev Returns the address that `account` has delegated their rewards to
     * @param account The address to get the delegatee for
     * @return The address that `account` has delegated their rewards to
     */
    function rewardDelegatee(address account) public view returns (address) {
        return _rewardDelegatee[account];
    }

    /**
     * @dev Internal function to delegate rewards
     * @param delegator The address delegating their rewards
     * @param delegatee The address to delegate the rewards to
     */
    function _delegateRewards(address delegator, address delegatee) internal virtual {
        address currentDelegate = _rewardDelegatee[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        _rewardDelegatee[delegator] = delegatee;

        emit RewardDelegateChanged(delegator, currentDelegate, delegatee);

        _moveRewardWeight(currentDelegate, delegatee, delegatorBalance);
    }

    /**
     * @dev Moves reward weight between addresses and updates checkpoints
     * @param from Source address of the weight
     * @param to Destination address for the weight
     * @param amount Amount of weight to move
     *
     * This function:
     * 1. Handles the core logic for reward weight accounting
     * 2. Creates checkpoints to track historical weight changes
     * 3. Handles special cases (minting/burning) via address(0)
     */
    function _moveRewardWeight(address from, address to, uint256 amount) internal virtual {
        // Only process if addresses are different and amount is positive
        if (from != to && amount > 0) {
            // If source is not address(0), reduce their weight
            if (from != address(0)) {
                uint256 oldValue = getRewardWeight(from);
                // Create checkpoint with reduced weight
                _rewardWeightCheckpoints[from].push(uint48(block.timestamp), SafeCast.toUint208(oldValue - amount));
                emit RewardWeightChanged(from, oldValue, oldValue - amount);
            }
            // If destination is not address(0), increase their weight
            if (to != address(0)) {
                uint256 oldValue = getRewardWeight(to);
                // Create checkpoint with increased weight
                _rewardWeightCheckpoints[to].push(uint48(block.timestamp), SafeCast.toUint208(oldValue + amount));
                emit RewardWeightChanged(to, oldValue, oldValue + amount);
            }
        }
    }

    /**
     * @dev Handles token transfers while managing reward weight updates
     * @param from Source address of the transfer
     * @param to Destination address of the transfer
     * @param amount Number of tokens being transferred
     *
     * This function extends the standard ERC20 transfer by:
     * 1. Executing the basic token transfer via super._update
     * 2. Handling reward weight updates considering:
     *    - Delegation relationships
     *    - Weight preservation settings
     *    - Special cases (minting/burning)
     *
     * Key Features:
     * - Respects reward weight preservation settings
     * - Updates delegated weights instead of direct addresses
     * - Handles both sender and receiver delegation chains
     */
    function _update(address from, address to, uint256 amount) internal override {
        // Perform standard ERC20 transfer
        super._update(from, to, amount);

        // Handle sender's reward weight update
        // Skip if minting or if weight preservation is enabled
        if (from != address(0) && !_preserveRewardWeight[from][msg.sender]) {
            address fromDelegatee = _rewardDelegatee[from];
            // Update delegatee's weight if delegation exists
            if (fromDelegatee != address(0)) {
                _moveRewardWeight(fromDelegatee, address(0), amount);
            }
        }

        // Handle receiver's reward weight update
        // Skip if burning or if weight preservation is enabled
        if (to != address(0) && !_preserveRewardWeight[from][msg.sender]) {
            address toDelegatee = _rewardDelegatee[to];
            // Update delegatee's weight if delegation exists
            if (toDelegatee != address(0)) {
                _moveRewardWeight(address(0), toDelegatee, amount);
            }
        }
    }
}
