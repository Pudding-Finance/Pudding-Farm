// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/access/Ownable.sol";
import "./libs/math/SafeMath.sol";

import "./PuddingToken.sol";
import "./MasterChef.sol";

/**
    Go production steps:
    1. Add pools.
    2. Setup a scheduled job to invoke compoundAll() regularly.
    3. If we decided to grant extra rewards to users by additional LP farm, we need to add a pool for this LP token, then invoke startLpTokenFarm by owner.
*/
contract VaultPudding is Ownable {
    using SafeMath for uint256;
    using SafeORC20 for IORC20;

    // Pool struct.
    struct Pool {
        string name;
        uint256 startLockBlockNumber; // Represents when the pool will start to lock.
        uint256 unlockPrincipalBlockNumber; // Represents when the principal of the pool is unlocked.
        uint256 unlockAllRewardsBlockNumber; // Represents when all rewards of the pool are unlocked.
        uint256 multiplier; // Multiplier when locking.
        uint256 effectiveMultiplier; // The current effective multiplier. It's used for reward redistribution when multiplier is going to change.
        uint256 totalPrincipal;
        uint256 totalReward;
    }

    // Pool state
    enum PoolState {OPEN, LOCKING, PRINCIPALUNLOCKED, ALLREWARDSUNLOCKED}

    // User has one wallet per pool.
    struct UserWallet {
        string poolName;
        uint256 principal;
        uint256 reward;
        uint256 maxReward; // This is used for unlocked reward calculation. The unlocked reward is propotional to the block number after unlockPrincipalBlockNumber of this value.
    }

    Pool[] public pools;
    mapping(string => uint256) poolIds; // Actually it stores id + 1 because we cannot differentiate default zero value or the first element.
    UserWallet[] public userWallets;
    mapping(address => mapping(string => uint256)) userWalletIds; // Actually it stores id + 1 because we cannot differentiate default zero value or the first element.

    // The PIPI TOKEN
    PuddingToken public pud;
    // The xPIPI TOKEN!
    PuddingBar public xPudding;
    // The MasterChef contract
    MasterChef public masterChef;
    // The LP token.
    ORC20 public lpToken;
    // The LP token pool id in masterChef.
    uint256 public lpTokenPid;

    // contract constructor
    constructor(
        PuddingToken _pud,
        PuddingBar _xPudding,
        MasterChef _masterChef
    ) public {
        pud = _pud;
        xPudding = _xPudding;
        masterChef = _masterChef;
    }

    // ------------------------------------------------------------------------
    // User write ABIs.

    // Deposit principal.
    function deposit(string memory _poolName, uint256 _amount) external {
        require(poolExists(_poolName), "Pool does not exist.");
        Pool storage pool = getPool(_poolName);
        require(
            block.number < pool.startLockBlockNumber,
            "Deposit is only allowed before pool locking."
        );

        // redistribute all balance before deposit.
        redistributeReward();
        pud.transferFrom(msg.sender, address(this), _amount);

        if (!userWalletExists(msg.sender, _poolName)) {
            // Create user wallet if not exists when deposit.
            userWallets.push(
                UserWallet({
                    poolName: _poolName,
                    principal: _amount,
                    reward: 0,
                    maxReward: 0
                })
            );
            userWalletIds[msg.sender][_poolName] = userWallets.length;
        } else {
            UserWallet storage userWallet =
                getUserWallet(msg.sender, _poolName);
            userWallet.principal = userWallet.principal.add(_amount);
        }

        pool.totalPrincipal = pool.totalPrincipal.add(_amount);

        // We need to compound all before transfering xPudding to sender so that masterChef has returned enough xPudding to us.
        compoundAll();
        // transfer xpud from our contract address to user address after entering staking.
        xPudding.transfer(address(msg.sender), _amount);
    }

    // Withdraw all principal and unlocked reward.
    function withdraw(string memory _poolName) external {
        require(poolExists(_poolName), "Pool does not exist.");
        Pool storage pool = getPool(_poolName);
        require(
            block.number >= pool.unlockPrincipalBlockNumber,
            "Withdraw is only allowed after pool unlocking."
        );

        require(
            userWalletExists(msg.sender, _poolName),
            "User has no wallet in this pool."
        );

        redistributeReward();

        UserWallet storage userWallet = getUserWallet(msg.sender, _poolName);
        require(
            userWallet.principal > 0,
            "User has no principal or withdrawn before in this pool."
        );

        uint256 lockingReward = getLockingReward(pool, userWallet.maxReward);
        uint256 remainingUnlockedReward = userWallet.reward.sub(lockingReward);
        uint256 withdrawAmount =
            userWallet.principal.add(remainingUnlockedReward);
        require(
            withdrawAmount > 0,
            "User has no balance to withdraw in this pool."
        );

        // We need to compound all before leaveStaking so that masterChef has enough money for withdraw.
        compoundAll();

        // transfer xpud from user address to our contract address before leaving staking
        xPudding.transferFrom(
            address(msg.sender),
            address(this),
            userWallet.principal
        );
        // Withdraw from masterChef then transfer to sender's address.
        masterChef.leaveStaking(withdrawAmount);
        pud.transfer(msg.sender, withdrawAmount);

        // Update our contract state.
        pool.totalPrincipal = pool.totalPrincipal.sub(userWallet.principal);
        pool.totalReward = pool.totalReward.sub(remainingUnlockedReward);
        userWallet.principal = 0;
        userWallet.reward = userWallet.reward.sub(remainingUnlockedReward);
    }

    // Withdraw unlocked reward.
    function harvest(string memory _poolName) external {
        require(poolExists(_poolName), "Pool does not exist.");
        Pool storage pool = getPool(_poolName);
        require(
            block.number >= pool.unlockPrincipalBlockNumber,
            "Harvest is only allowed after pool unlocking."
        );

        require(
            userWalletExists(msg.sender, _poolName),
            "User has no wallet in this pool."
        );

        redistributeReward();

        UserWallet storage userWallet = getUserWallet(msg.sender, _poolName);
        uint256 lockingReward = getLockingReward(pool, userWallet.maxReward);
        uint256 remainingUnlockedReward = userWallet.reward.sub(lockingReward);

        require(
            remainingUnlockedReward > 0,
            "User has no unlocked reward to harvest in this pool."
        );

        // We need to compound all before leaveStaking so that masterChef has enough money for withdraw.
        compoundAll();

        // Havest from masterChef then transfer to sender's address.
        masterChef.leaveStaking(remainingUnlockedReward);
        pud.transfer(address(msg.sender), remainingUnlockedReward);

        // Update our contract state.
        pool.totalReward = pool.totalReward.sub(remainingUnlockedReward);
        userWallet.reward = userWallet.reward.sub(remainingUnlockedReward);
    }

    // Compound all pool's principal & reward by calling masterChef contract ABI.
    // This is costly so anyone who wants to pay gas can execute it.
    function compoundAll() public {
        // harvest all from masterChef.
        masterChef.leaveStaking(0);
        if (lpTokenPid != 0) {
            // withdraw all lp rewards from masterChef.
            masterChef.withdraw(lpTokenPid, 0);
        }
        // get current pud balance.
        uint256 reward = pud.balanceOf(address(this));
        // stake all balance to masterChef as compound.
        pud.approve(address(masterChef), reward);
        masterChef.enterStaking(reward);

        // If pool state changes, we need to redistribute all rewards then update effective pool multipliers.
        if (shouldEffectivePoolMultiplierChange()) {
            redistributeReward();
            updateEffectivePoolMultiplier();
        }
    }

    // This will recalculate the latest reward according to masterChef's ABI to update our contract state.
    // This is really costly so anyone who wants to pay gas can execute it.
    function redistributeReward() public {
        uint256 totalWeightedSum = currentTotalWeightedSum();
        if (totalWeightedSum == 0) {
            // No redistribution required.
            return;
        }

        // Distribute new earnings to all user wallets according to multiplier * totalBalance
        uint256 totalNewReward = getUndistributedReward();
        uint256 length = userWallets.length;
        for (uint256 uwid = 0; uwid < length; ++uwid) {
            UserWallet storage userWallet = userWallets[uwid];
            Pool storage pool = getPool(userWallet.poolName);
            uint256 newReward =
                totalNewReward
                    .mul(userWallet.principal.add(userWallet.reward))
                    .mul(pool.effectiveMultiplier)
                    .div(totalWeightedSum);
            userWallet.reward = userWallet.reward.add(newReward);
            userWallet.maxReward = userWallet.maxReward < userWallet.reward
                ? userWallet.reward
                : userWallet.maxReward;
            pool.totalReward = pool.totalReward.add(newReward);
        }
    }

    // ------------------------------------------------------------------------
    // User read ABIs.

    function getPoolInfo(string memory _poolName)
        external
        view
        returns (PoolState state)
    {
        require(poolExists(_poolName), "Pool does not exist.");
        Pool storage pool = getPool(_poolName);
        return getPoolState(pool);
    }

    function getUserInfo(string memory _poolName, address _user)
        external
        view
        returns (
            uint256 principal,
            uint256 lockedReward,
            uint256 unlockedReward
        )
    {
        require(poolExists(_poolName), "Pool does not exist.");
        Pool storage pool = getPool(_poolName);

        if (!userWalletExists(_user, _poolName)) {
            return (0, 0, 0);
        }

        UserWallet storage userWallet = getUserWallet(_user, _poolName);

        uint256 totalWeightedSum = currentTotalWeightedSum();
        uint256 newReward;
        if (totalWeightedSum > 0) {
            newReward = getUndistributedReward()
                .mul(userWallet.principal.add(userWallet.reward))
                .mul(pool.effectiveMultiplier)
                .div(totalWeightedSum);
        } else {
            // No reward distribution anymore.
            newReward = 0;
        }

        uint256 expectedMaxReward = userWallet.maxReward.add(newReward);
        uint256 expectedLockingReward =
            getLockingReward(pool, expectedMaxReward);
        uint256 expectedRemainingUnlockedReward =
            userWallet.reward.add(newReward).sub(expectedLockingReward);

        return (
            userWallet.principal,
            expectedLockingReward,
            expectedRemainingUnlockedReward
        );
    }

    // ------------------------------------------------------------------------
    // Owner ABIs.

    function addPool(
        string memory _poolName,
        uint256 _startLockBlockNumber,
        uint256 _unlockPrincipalBlockNumber,
        uint256 _unlockAllRewardsBlockNumber,
        uint256 _multiplier
    ) external onlyOwner {
        require(!poolExists(_poolName), "pool already exists.");

        redistributeReward();

        pools.push(
            Pool({
                name: _poolName,
                startLockBlockNumber: _startLockBlockNumber,
                unlockPrincipalBlockNumber: _unlockPrincipalBlockNumber,
                unlockAllRewardsBlockNumber: _unlockAllRewardsBlockNumber,
                multiplier: _multiplier,
                effectiveMultiplier: 1,
                totalPrincipal: 0,
                totalReward: 0
            })
        );
        poolIds[_poolName] = pools.length;

        updateEffectivePoolMultiplier();
    }

    function updatePoolLifetime(
        string memory _poolName,
        uint256 _startLockBlockNumber,
        uint256 _unlockPrincipalBlockNumber,
        uint256 _unlockAllRewardsBlockNumber
    ) external onlyOwner {
        require(poolExists(_poolName), "pool does not exist.");

        redistributeReward();

        Pool storage pool = getPool(_poolName);
        pool.startLockBlockNumber = _startLockBlockNumber;
        pool.unlockPrincipalBlockNumber = _unlockPrincipalBlockNumber;
        pool.unlockAllRewardsBlockNumber = _unlockAllRewardsBlockNumber;

        if (shouldEffectivePoolMultiplierChange()) {
            updateEffectivePoolMultiplier();
        }
    }

    function setPoolMultiplier(string memory _poolName, uint256 _multiplier)
        external
        onlyOwner
    {
        require(poolExists(_poolName), "pool does not exist.");

        redistributeReward();

        Pool storage pool = getPool(_poolName);
        pool.multiplier = _multiplier;

        if (shouldEffectivePoolMultiplierChange()) {
            updateEffectivePoolMultiplier();
        }
    }

    // This owner ABI should be called when owner wants to start LP staking.
    // With this LP staking, our users can get extra rewards.
    // Before calling this ABI, the corresponding LP token pool should have already been added in MasterChef.
    function startLpTokenFarm(uint256 _lpTokenPid, ORC20 _lpToken)
        external
        onlyOwner
    {
        require(lpTokenPid == 0, "LP token has already been added for farm.");
        require(_lpTokenPid != 0, "Invalid input LP token pid.");

        lpToken = _lpToken;
        lpTokenPid = _lpTokenPid;

        // Mint 1 lpToken and deposit to masterChef.
        // The amount can be any positive value as it does not affect how many pud are rewarded in total to us.
        // lpToken.mint(1);
        lpToken.approve(address(masterChef), 1 ether);
        masterChef.deposit(lpTokenPid, 1 ether);
    }

    // This ABI will leave all staking from masterChef.
    function leaveStakingAll() external onlyOwner {
        (uint256 stakingPuddingAmount, ) =
            masterChef.userInfo(0, address(this));
        uint256 xPuddingBalance = xPudding.balanceOf(address(this));

        if (stakingPuddingAmount > xPuddingBalance) {
            // transfer xpud from owner address to our contract address before leaving staking
            xPudding.transferFrom(
                address(msg.sender),
                address(this),
                stakingPuddingAmount - xPuddingBalance
            );
        }

        // withdraw and harvest all from masterChef.
        masterChef.leaveStaking(stakingPuddingAmount);

        // withdraw all lp rewards from masterChef if exists.
        if (lpTokenPid != 0) {
            masterChef.withdraw(lpTokenPid, 1 ether);
        }
    }

    // This ABI will withdraw all pud balance to the owner address.
    // You may want to invoke leaveStakingAll first to get all staking pud from masterChef to this contract address.
    // Notice this ABI is dangerous, after invoking we can never restore the correct user wallets state.
    // i.e. This ABI should only be invoked when you want to destroy this PuddingAuto contract.
    function withdrawAll() external onlyOwner {
        // get current pud balance.
        uint256 pudBalance = pud.balanceOf(address(this));
        // transfer all pud to owner account.
        pud.transfer(msg.sender, pudBalance);

        // withdraw all lp tokens
        if (lpTokenPid != 0) {
          uint256 lpBalance = lpToken.balanceOf(address(this));
          lpToken.transfer(owner(), lpBalance);
        }
    }

    // ------------------------------------------------------------------------
    // private ABIs.

    function poolExists(string memory _poolName) private view returns (bool) {
        return poolIds[_poolName] > 0;
    }

    function getPool(string memory _poolName)
        private
        view
        returns (Pool storage)
    {
        return pools[poolIds[_poolName] - 1];
    }

    function getPoolState(Pool storage _pool) private view returns (PoolState) {
        uint256 currentBlockNumber = block.number;
        if (currentBlockNumber < _pool.startLockBlockNumber) {
            return PoolState.OPEN;
        }
        if (currentBlockNumber < _pool.unlockPrincipalBlockNumber) {
            return PoolState.LOCKING;
        }
        if (currentBlockNumber < _pool.unlockAllRewardsBlockNumber) {
            return PoolState.PRINCIPALUNLOCKED;
        }
        return PoolState.ALLREWARDSUNLOCKED;
    }

    function shouldEffectivePoolMultiplierChange() private view returns (bool) {
        uint256 length = pools.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            Pool storage pool = pools[pid];
            PoolState poolState = getPoolState(pool);
            if (poolState == PoolState.OPEN) {
                if (pool.effectiveMultiplier != 1) {
                    return true;
                }
            } else if (poolState == PoolState.LOCKING) {
                if (pool.effectiveMultiplier != pool.multiplier) {
                    return true;
                }
            } else {
                // PoolState.PRINCIPALUNLOCKED or PoolState.ALLREWARDSUNLOCKED
                if (pool.effectiveMultiplier != 0) {
                    return true;
                }
            }
        }
        return false;
    }

    function updateEffectivePoolMultiplier() private {
        uint256 length = pools.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            Pool storage pool = pools[pid];
            PoolState poolState = getPoolState(pool);
            if (poolState == PoolState.OPEN) {
                pool.effectiveMultiplier = 1;
            } else if (poolState == PoolState.LOCKING) {
                pool.effectiveMultiplier = pool.multiplier;
            } else {
                // PoolState.PRINCIPALUNLOCKED or PoolState.ALLREWARDSUNLOCKED
                pool.effectiveMultiplier = 0;
            }
        }
    }

    function userWalletExists(address _signer, string memory _poolName)
        private
        view
        returns (bool)
    {
        return userWalletIds[_signer][_poolName] > 0;
    }

    function getUserWallet(address _signer, string memory _poolName)
        private
        view
        returns (UserWallet storage)
    {
        return userWallets[userWalletIds[_signer][_poolName] - 1];
    }

    function getLockingReward(Pool storage _pool, uint256 _totalReward)
        private
        view
        returns (uint256)
    {
        PoolState poolState = getPoolState(_pool);
        if (poolState == PoolState.OPEN) {
            return _totalReward;
        } else if (poolState == PoolState.LOCKING) {
            return _totalReward;
        } else if (poolState == PoolState.PRINCIPALUNLOCKED) {
            return
                _totalReward
                    .mul(_pool.unlockAllRewardsBlockNumber.sub(block.number))
                    .div(
                    _pool.unlockAllRewardsBlockNumber.sub(
                        _pool.unlockPrincipalBlockNumber
                    )
                );
        } else {
            // PoolState.ALLREWARDSUNLOCKED
            return 0;
        }
    }

    function getUndistributedReward() private view returns (uint256) {
        (uint256 stakingAmount, ) = masterChef.userInfo(0, address(this));
        uint256 reward = masterChef.pendingPudding(0, address(this));
        uint256 latestTotalBalanceFromMasterChef = stakingAmount.add(reward);

        if (lpTokenPid != 0) {
            uint256 lpFarmReward =
                masterChef.pendingPudding(lpTokenPid, address(this));
            latestTotalBalanceFromMasterChef = latestTotalBalanceFromMasterChef
                .add(lpFarmReward);
        }

        // Undistributed rewards / New earnings = latestTotalBalanceFromMasterChef - currentTotalBalance
        uint256 length = pools.length;
        uint256 totalBalance = 0;
        for (uint256 pid = 0; pid < length; ++pid) {
            totalBalance = totalBalance.add(pools[pid].totalPrincipal).add(
                pools[pid].totalReward
            );
        }
        return latestTotalBalanceFromMasterChef.sub(totalBalance);
    }

    function currentTotalWeightedSum() private view returns (uint256) {
        uint256 length = pools.length;
        uint256 totalWeightedSum = 0;
        for (uint256 pid = 0; pid < length; ++pid) {
            Pool storage pool = pools[pid];
            totalWeightedSum = totalWeightedSum.add(
                pool.effectiveMultiplier.mul(
                    pool.totalPrincipal.add(pool.totalReward)
                )
            );
        }
        return totalWeightedSum;
    }
}
