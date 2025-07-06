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
// Deploy tokens instantly with no liquidity needed. 
// The most optimized platform for token creation and deployment.

pragma solidity ^0.8.30;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IWETH {
    function withdraw(uint256 amount) external;
}
interface IFactory{
    function getTokenPrice(address val) external view returns (uint256);
}
contract RavaStake is Ownable, ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
    }

    struct PoolInfo {
        IERC20 token;           
        uint256 allocPoint;      
        uint256 totalDeposit;
        uint256 lastRewardTime; 
        uint256 accRewardsPerShare; 
    }

    struct PoolView {
        uint256 pid;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 rewardsPerSecond;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        address token;
        string symbol;
        string name;
        uint8 decimals;
        uint256 startTime;
        uint256 bonusEndTime;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
    }

    IERC20 public rewardToken;
    uint256 public maxStakingPerUser;
    uint256 public rewardPerSecond;

    uint256 public BONUS_MULTIPLIER = 1;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 private totalAllocPoint = 0;
    uint256 public startTime;
    uint256 public bonusEndTime;
    uint256 public maxDuration = 60 days;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public FACTORY;
    EnumerableSet.AddressSet private _pairs;
    mapping(address => uint256) public LpOfPid;
    EnumerableSet.AddressSet private _callers;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 rewards);

    constructor(
        address _factoryv3,
        address _RAVA
    ) Ownable(msg.sender) {
        rewardToken = IERC20(WETH);
        rewardPerSecond = 0;
        startTime = block.timestamp;
        bonusEndTime = block.timestamp;
        maxStakingPerUser = type(uint256).max;
        FACTORY = _factoryv3; 

        addCaller(_factoryv3); 
        addCaller(msg.sender); // owner

        add(100, _RAVA, true);
    }

    function stopReward() public onlyOwner {
        bonusEndTime = block.timestamp;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndTime) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    function add(uint256 _allocPoint, address _token, bool _withUpdate) public onlyOwner {
        require(_token != address(0), "RavaStake: _token is the zero address");

        require(!EnumerableSet.contains(_pairs, _token), "RavaStake: _token is already added to the pool");
        EnumerableSet.add(_pairs, _token);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                token: IERC20(_token),
                allocPoint: _allocPoint,
                totalDeposit: 0,
                lastRewardTime: lastRewardTime,
                accRewardsPerShare: 0
            })
        );
        LpOfPid[_token] = poolInfo.length - 1;
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        massUpdatePools();
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setMaxStakingPerUser(uint256 amount) public onlyOwner {
        maxStakingPerUser = amount;
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid <= poolInfo.length - 1, "RavaStake: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 tokenReward = multiplier.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e18).sub(user.rewardDebt);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 tokenReward = multiplier.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public nonReentrant{
        require(_pid <= poolInfo.length - 1, "RavaStake: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(_amount.add(user.amount) <= maxStakingPerUser, "RavaStake: exceed max stake");

        updatePool(_pid);
        
        uint256 reward;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                uint256 bal = rewardToken.balanceOf(address(this));
                if(bal >= pending) {
                    reward = pending;
                } else {
                    reward = bal;
                }
            }
        }

        if(_amount > 0) {
            uint256 oldBal = pool.token.balanceOf(address(this));
            pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.token.balanceOf(address(this)).sub(oldBal);

            user.amount = user.amount.add(_amount);
            pool.totalDeposit = pool.totalDeposit.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        if (reward > 0) {
            // weth unwrap
            IWETH(address(rewardToken)).withdraw(reward);

            // send reward
            (bool success, ) = msg.sender.call{ value: reward }("");
            require(success, "RavaStake: ETH transfer failed");
        }
        
        emit Deposit(msg.sender, _amount);
    }

    function injectRewards(uint256 amount) public onlyCaller nonReentrant{
        _injectRewardsWithTime(amount);
    }

    function _injectRewardsWithTime(uint256 amount) internal {
        massUpdatePools();

        uint256 oldBal = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(_msgSender(), address(this), amount);
        uint256 realAmount = rewardToken.balanceOf(address(this)).sub(oldBal);

        uint256 remainingSeconds = bonusEndTime > block.timestamp ? bonusEndTime.sub(block.timestamp) : 0;
        uint256 remainingBal = rewardPerSecond.mul(remainingSeconds);

        uint256 daysPerEther = 1 days / 2;
        uint256 requestedAdditionalTime = realAmount.mul(daysPerEther).div(1 ether);
        
        if(requestedAdditionalTime < 1 hours) {
            requestedAdditionalTime = 1 hours;
        }

        // Max allowed bonusEndTime
        uint256 maxAllowedEndTime = block.timestamp.add(maxDuration);
        
        uint256 actualAdditionalTime = 0;
        
        if(bonusEndTime < maxAllowedEndTime) {
            uint256 possibleNewEndTime = bonusEndTime.add(requestedAdditionalTime);
            
            if(possibleNewEndTime <= maxAllowedEndTime) {
                actualAdditionalTime = requestedAdditionalTime;
                bonusEndTime = possibleNewEndTime;
            } else {
                actualAdditionalTime = maxAllowedEndTime.sub(bonusEndTime);
                bonusEndTime = maxAllowedEndTime;
            }
        }

        uint256 totalTime = remainingSeconds.add(actualAdditionalTime);
        uint256 totalRewards = remainingBal.add(realAmount);
        
        if(totalTime > 0) {
            rewardPerSecond = totalRewards.div(totalTime);
        }

    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "RavaStake: Withdraw with insufficient balance");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
        
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDeposit = pool.totalDeposit.sub(_amount);
            pool.token.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        uint256 rewards;
        if(pending > 0) {
            uint256 bal = rewardToken.balanceOf(address(this));
            if(bal >= pending) {
                rewards = pending;
            } else {
                rewards = bal;
            }
        }
        
        // weth unwrap
        IWETH(address(rewardToken)).withdraw(rewards);

        // send reward
        (bool success, ) = msg.sender.call{ value: rewards }("");
        require(success, "RavaStake: ETH transfer failed");

        emit Withdraw(msg.sender, _amount, rewards);
    }

    function getPoolView(uint256 pid) public view returns (PoolView memory) {
        require(pid < poolInfo.length, "RavaStake: pid out of range");
        PoolInfo memory pool = poolInfo[pid];
        IERC20Metadata token = IERC20Metadata(address(pool.token));
        uint256 rewardsPerSecond = pool.allocPoint.mul(rewardPerSecond).div(totalAllocPoint);
        return
            PoolView({
                pid: pid,
                allocPoint: pool.allocPoint,
                lastRewardTime: pool.lastRewardTime,
                accRewardPerShare: pool.accRewardsPerShare,
                rewardsPerSecond: rewardsPerSecond,
                totalAmount: pool.totalDeposit,
                token: address(token),
                symbol: token.symbol(),
                name: token.name(),
                decimals: token.decimals(),
                startTime: startTime,
                bonusEndTime: bonusEndTime
            });
    }

    function getAPR(uint256 pid) public view returns (uint256 apr) {
        require(pid < poolInfo.length, "RavaStake: pid out of range");
        
        PoolInfo memory pool = poolInfo[pid];
        
        if (pool.totalDeposit == 0) {
            return 0;
        }
        
        address token = address(pool.token);
        uint256 tokenPrice = IFactory(FACTORY).getTokenPrice(token); 
        
        uint256 poolAllocPoint = pool.allocPoint;
        uint256 yearlyReward = rewardPerSecond * 365 days * poolAllocPoint / totalAllocPoint;
        
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        uint256 totalValueInWeth = pool.totalDeposit * tokenPrice / (10 ** tokenDecimals);
        
        if (totalValueInWeth > 0) {
            apr = (yearlyReward * 10000) / totalValueInWeth;
        } else {
            apr = 0;
        }
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address token, address account) public view returns (UserView memory) {
        uint256 pid = LpOfPid[token];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingReward(pid, account);
        uint256 lpBalance = IERC20(token).balanceOf(account);
        return
            UserView({
                stakedAmount: user.amount,
                unclaimedRewards: unclaimedRewards,
                lpBalance: lpBalance
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address token;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            token = address(poolInfo[i].token);
            views[i] = getUserView(token, account);
        }
        return views;
    }

    function addCaller(address val) public onlyOwner() {
        require(val != address(0), "RavaStake: val is the zero address");
        _callers.add(val);
    }

    function delCaller(address caller) public onlyOwner returns (bool) {
        require(caller != address(0), "RavaStake: caller is the zero address");
        return _callers.remove(caller);
    }

    function getCallers() public view returns (address[] memory ret) {
        return _callers.values();
    }

    function setFactory(address val) public onlyOwner{
        FACTORY = val;
    }

    modifier onlyCaller() {
        require(_callers.contains(_msgSender()), "onlyCaller");
        _;
    }

    receive() external payable {} // for weth unwrap

}