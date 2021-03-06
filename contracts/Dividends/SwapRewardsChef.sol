// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IWrappedNative.sol";

contract SwapRewardsChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times 1e18. See below.
        uint256 currentDepositAmount; // Current total deposit amount in this pool
    }

    address public wrappedNativeAddress;

    // The reward token
    IERC20 public rewardToken;
    // Reward tokens created per block.
    uint256 public rewardsPerBlock;

    // Emission Settings
    uint256 public denominationEmitAmount = 403200; //Blocks
    uint256 public minimumEmitAmount = 0; //Min Output Per Block
    uint256 public maximumEmitAmount = 1 ether; //Max Output Per Block

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when mining starts.
    uint256 public startBlock;

    uint256 public remainingRewards = 0;

    event Harvest(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event UpdateEmissionSettings(
        address indexed user,
        uint256 denomination,
        uint256 minimum,
        uint256 maximum,
        uint256 rewardsPerBlock
    );
    event RescueTokens(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        address _wrappedNativeAddress
    ) public {
        rewardToken = _rewardToken;

        poolInfo.push(
            PoolInfo({
                lpToken: _stakeToken,
                allocPoint: 100,
                lastRewardBlock: startBlock,
                accRewardPerShare: 0,
                currentDepositAmount: 0
            })
        );

        wrappedNativeAddress = _wrappedNativeAddress;

        totalAllocPoint = 100;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        private
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending rewards on frontend.
    function pendingRewards(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.currentDepositAmount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            //calculate total rewards based on remaining funds
            if (remainingRewards > 0) {
                uint256 multiplier = getMultiplier(
                    pool.lastRewardBlock,
                    block.number
                );
                uint256 totalRewards = multiplier
                    .mul(rewardsPerBlock)
                    .mul(pool.allocPoint)
                    .div(totalAllocPoint);
                totalRewards = Math.min(totalRewards, remainingRewards);
                accRewardPerShare = accRewardPerShare.add(
                    totalRewards.mul(1e18).div(lpSupply)
                );
            }
        }
        return
            user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        PoolInfo storage pool = poolInfo[0];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.currentDepositAmount;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        if (remainingRewards == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        //calculate total rewards based on remaining funds
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 totalRewards = multiplier
            .mul(rewardsPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        totalRewards = Math.min(totalRewards, remainingRewards);
        remainingRewards = remainingRewards.sub(totalRewards);
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            totalRewards.mul(1e18).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function income(uint256 _amount) external nonReentrant {
        updatePool();
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        remainingRewards = remainingRewards.add(_amount);
        updateEmissionRate();
    }

    function updateEmissionRate() private {
        if (remainingRewards > 0) {
            rewardsPerBlock = remainingRewards.div(denominationEmitAmount);
            rewardsPerBlock = Math.min(maximumEmitAmount, rewardsPerBlock);
            rewardsPerBlock = Math.max(minimumEmitAmount, rewardsPerBlock);
        } else {
            rewardsPerBlock = 0;
        }
    }

    // Deposit LP tokens to Chef
    function deposit(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accRewardPerShare)
                .div(1e18)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
                emit Harvest(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.currentDepositAmount = pool.currentDepositAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw LP tokens from Chef.
    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
            emit Harvest(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.currentDepositAmount = pool.currentDepositAmount.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.currentDepositAmount = pool.currentDepositAmount.sub(amount);
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // Safe rewards transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 balance = rewardToken.balanceOf(address(this));
        uint256 transferAmount = Math.min(balance, _amount);
        if (address(rewardToken) == wrappedNativeAddress) {
            //If the reward token is a wrapped native token, we will unwrap it and send native
            IWrappedNative(wrappedNativeAddress).withdraw(transferAmount);
            safeTransferETH(_to, transferAmount);
        } else {
            bool transferSuccess = rewardToken.transfer(_to, transferAmount);
            require(transferSuccess, "safeRewardTransfer: transfer failed");
        }
    }

    //For unwrapping native tokens
    receive() external payable {}

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "safeTransferETH: ETH_TRANSFER_FAILED");
    }

    function updateEmissionSettings(
        uint256 denomination,
        uint256 minimum,
        uint256 maximum
    ) external onlyOwner {
        updatePool();
        denominationEmitAmount = denomination;
        minimumEmitAmount = minimum;
        maximumEmitAmount = maximum;
        updateEmissionRate();

        emit UpdateEmissionSettings(
            msg.sender,
            denomination,
            minimum,
            maximum,
            rewardsPerBlock
        );
    }

    //New function to trigger harvest for a specific user and pool
    //A specific user address is provided to facilitate aggregating harvests on multiple chefs
    //Also, it is harmless monetary-wise to help someone else harvests
    function harvestFor(address _user) public nonReentrant {
        //Limit to self or delegated harvest to avoid unnecessary confusion
        require(
            msg.sender == _user || tx.origin == _user,
            "harvestFor: FORBIDDEN"
        );
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accRewardPerShare)
                .div(1e18)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeRewardTransfer(_user, pending);
                user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(
                    1e18
                );
                emit Harvest(_user, pending);
            }
        }
    }

    function rescueToken(address token, address addressForReceive)
        external
        onlyOwner
    {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(addressForReceive, balance);
        emit RescueTokens(msg.sender, token, balance);
    }
}
