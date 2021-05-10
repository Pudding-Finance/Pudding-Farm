pragma solidity 0.6.12;

import "./libs/math/SafeMath.sol";
import "./libs/token/ORC20/IORC20.sol";
import "./libs/token/ORC20/SafeORC20.sol";
import "./libs/access/Ownable.sol";
import "./libs/utils/ReentrancyGuard.sol";
import "@nomiclabs/buidler/console.sol";

contract ePuddingHooChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeORC20 for IORC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IORC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. PUDs to distribute per block.
        uint256 lastRewardBlock; // Last block number that PUDs distribution occurs.
        uint256 accPuddingPerShare; // Accumulated PUDs per share, times 1e12. See below.
    }

    // The PUD TOKEN!
    IORC20 public ePudding;

    // uint256 public maxStaking;

    // PUD tokens created per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when PUD mining starts.
    uint256 public startBlock;
    // The block number when PUD mining ends.
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IORC20 _ePudding,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        ePudding = _ePudding;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _ePudding,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                accPuddingPerShare: 0
            })
        );

        totalAllocPoint = 1000;
        // maxStaking = 50000000000000000000;
    }

    function stopReward() public onlyOwner {
        bonusEndBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accPuddingPerShare = pool.accPuddingPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 pudReward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accPuddingPerShare = accPuddingPerShare.add(
                pudReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accPuddingPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 pudReward =
            multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        pool.accPuddingPerShare = pool.accPuddingPerShare.add(
            pudReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function safeTransferHOO(address to, uint256 value) internal {
        console.log('to', to);
        (bool success, ) = to.call{gas: 23000, value: value}(new bytes(0));
        require(success, "TransferHelper: HOO_TRANSFER_FAILED");
    }

    // Stake ePUD tokens to ePuddingChef
    function deposit(uint256 _amount) public nonReentrant {
        console.log("deposit");
        uint256 pending = 0;
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        // require (_amount.add(user.amount) <= maxStaking, 'exceed max stake');

        updatePool(0);
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accPuddingPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (pending > 0) {
                console.log("1111", 111);
                safeTransferHOO(address(msg.sender), pending);
                console.log("222", 222);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accPuddingPerShare).div(1e12);
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw ePUD tokens from STAKING.
    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending =
            user.amount.mul(pool.accPuddingPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            safeTransferHOO(address(msg.sender), pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPuddingPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount < address(this).balance, "not enough token");
        safeTransferHOO(address(msg.sender), _amount);
    }

    function recieveReward() external payable {
       require(msg.sender != address(0));
       require(msg.value != 0);
     }
}
