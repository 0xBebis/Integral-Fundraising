// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../boring-solidity/libraries/BoringMath.sol";
import "../boring-solidity/BoringBatchable.sol";
import "../boring-solidity/BoringOwnable.sol";
import "./libraries/SignedSafeMath.sol";
import "./interfaces/IRewarder.sol";
import "./interfaces/IMasterChef.sol";

/// @notice The (older) MasterChef contract gives out a constant number of RELIC tokens per block.
/// It is the only address with minting rights for RELIC.
/// The idea for this MasterChef V2 (MCV2) contract is therefore to be the owner of a dummy token
/// that is deposited into the MasterChef V1 (MCV1) contract.
/// The allocation point for this pool on MCV1 is the total allocation point for all pools that receive double incentives.
contract MasterChefV2 is Memento, BoringOwnable, BoringBatchable {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringERC20 for IERC20;
    using SignedSafeMath for int256;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of RELIC entitled to the user.
    struct PositionInfo {
        uint256 amount;
        int256 rewardDebt;
        uint256 entryAmount; // user's initial deposit.
        uint40 entryTime; // user's entry into the pool.
        bool exempt; // exemption from vesting cliff.
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of RELIC to distribute per block.
    struct PoolInfo {
        uint128 accRelicPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;

        uint256 curveAddress;
        uint256 averageEntry;
    }

    /// @notice Address of RELIC contract.
    IERC20 public immutable RELIC;
    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;
    /// @notice Address of each `IRewarder` contract in MCV2.
    IRewarder[] public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (uint256 => positionInfo)) public positionInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 private constant BASE_RELIC_PER_BLOCK = 1e12;
    uint256 private constant ACC_RELIC_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accRELICPerShare);
    event LogInit();

    /// @param _MASTER_CHEF The RELICSwap MCV1 contract address.
    /// @param _RELIC The RELIC token contract address.
    /// @param _MASTER_PID The pool ID of the dummy token on the base MCV1 contract.
    constructor(IERC20 _relic) public {
        RELIC = _relic;
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 allocPoint, IERC20 _lpToken, IRewarder _rewarder) public onlyOwner {
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(PoolInfo({
            allocPoint: allocPoint.to64(),
            lastRewardBlock: lastRewardBlock.to64(),
            accRelicPerShare: 0
        }));
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's RELIC allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(uint256 _pid, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint.to64();
        if (overwrite) { rewarder[_pid] = _rewarder; }
        emit LogSetPool(_pid, _allocPoint, overwrite ? _rewarder : rewarder[_pid], overwrite);
    }

    /// @notice View function to see pending RELIC on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending RELIC reward for a given user.
    function pendingRelic(uint256 _pid, uint256 positionId) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        PositionInfo storage position = positionInfo[_pid][positionId];
        uint256 accRelicPerShare = pool.accRelicPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number.sub(pool.lastRewardBlock);
            uint256 relicReward = blocks.mul(BASE_RELIC_PER_BLOCK).mul(pool.allocPoint) / totalAllocPoint;
            accRelicPerShare = accRelicPerShare.add(relicReward.mul(ACC_RELIC_PRECISION) / lpSupply);
        }
        pending = int256(position.amount.mul(accRelicPerShare) / ACC_RELIC_PRECISION).sub(position.rewardDebt).toUInt256();
    }

    function createNewPosition(address to, uint256 pid) public returns (bytes32) {
      mint(to, pid);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 blocks = block.number.sub(pool.lastRewardBlock);
                uint256 relicReward = blocks.mul(relicPerBlock()).mul(pool.allocPoint) / totalAllocPoint;
                pool.accRelicPerShare = pool.accRelicPerShare.add((relicReward.mul(ACC_RELIC_PRECISION) / lpSupply).to128());
            }
            pool.lastRewardBlock = block.number.to64();
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.accRelicPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCV2 for RELIC allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, uint256 positionId) public {
        PoolInfo memory pool = updatePool(pid);
        PositionInfo storage position = positionInfo[pid][positionId];
        address to = get(_tokenOwners, positionId);

        // Effects
        position.amount = position.amount.add(amount);
        position.rewardDebt = position.rewardDebt.add(int256(amount.mul(pool.accRelicPerShare) / ACC_RELIC_PRECISION));

        // Interactions
        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onRelicReward(pid, to, to, 0, position.amount);
        }

        _updateEntryTime(amount, positionId);
        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, uint256 positionId) public {
        PoolInfo memory pool = updatePool(pid);
        PositionInfo storage position = positionInfo[pid][[positionId]];
        address to = get(_tokenOwners, positionId);

        // Effects
        position.rewardDebt = position.rewardDebt.sub(int256(amount.mul(pool.accRelicPerShare) / ACC_RELIC_PRECISION));
        position.amount = position.amount.sub(amount);

        // Interactions
        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onRelicReward(pid, msg.sender, to, 0, position.amount);
        }

        _updateEntryTime(amount, positionId);
        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of RELIC rewards.
    function harvest(uint256 pid, uint256 positionId) public {
        PoolInfo memory pool = updatePool(pid);
        PositionInfo storage position = positionInfo[pid][positionId];
        address to = get(_tokenOwners, positionId);
        int256 accumulatedRelic = int256(position.amount.mul(pool.accRelicPerShare) / ACC_RELIC_PRECISION);
        uint256 _pendingRelic = accumulatedRelic.sub(position.rewardDebt).toUInt256();
        uint256 _curvedRelic = modifyEmissions(_pendingRelic, msg.sender, pid);

        // Effects
        position.rewardDebt = accumulatedRelic;

        // Interactions
        if (_pendingRelic != 0) {
            RELIC.safeTransfer(to, _curvedRelic);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onRelicReward( pid, msg.sender, to, _pendingRelic, position.amount);
        }

        emit Harvest(msg.sender, pid, _curvedRelic);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and RELIC rewards.
    function withdrawAndHarvest(uint256 pid, uint256 amount, uint256 positionId) public {
        PoolInfo memory pool = updatePool(pid);
        PositionInfo storage position = positionInfo[pid][positionId];
        address to = get(_tokenOwners, positionId);
        int256 accumulatedRelic = int256(position.amount.mul(pool.accRelicPerShare) / ACC_RELIC_PRECISION);
        uint256 _pendingRelic = accumulatedRelic.sub(position.rewardDebt).toUInt256();
        uint256 _curvedRelic = modifyEmissions(_pendingRelic, msg.sender, pid);

        // Effects
        position.rewardDebt = accumulatedRelic.sub(int256(amount.mul(pool.accRelicPerShare) / ACC_RELIC_PRECISION));
        position.amount = position.amount.sub(amount);

        // Interactions
        RELIC.safeTransfer(to, _curvedRelic);

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onRelicReward(pid, msg.sender, to, _curvedRelic, position.amount);
        }

        _updateEntryTime(amount, positionId, Action.WITHDRAW);
        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingRelic);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, uint256 positionId) public {
        PositionInfo storage position = positionInfo[pid][positionId];
        uint256 amount = position.amount;
        address to = get(_tokenOwners, positionId);
        position.amount = 0;
        position.rewardDebt = 0;

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onRelicReward(pid, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        _updateEntryTime(amount, positionId);
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}
