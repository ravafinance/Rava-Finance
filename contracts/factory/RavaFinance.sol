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
import "./erc20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IToken {
    function creator() external view returns (address);
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function pairFee() external view returns(uint24);
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function factory() external view returns (address);
    function WETH9() external view returns (address);

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);

    function mint(MintParams calldata params) external returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IRavaStake{
    function injectRewards(uint256 amount) external;
    function injectRewardsWithTime(uint256 amount, uint256 rewardsSeconds) external;
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract RavaFinance is ReentrancyGuard{
    event ERC20TokenCreated(address tokenAddress);

    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        address deployer;
        uint256 time;
        string metadata;
        uint24 fee;
        address pair;
        uint256 positionId;
    }

    mapping(uint256 => TokenInfo) public deployedTokens;
    uint256 public tokenCount = 1;
    address public owner;

    address public constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    uint256 constant Q96 = 2 ** 96;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant DEAD = address(0x000000000000000000000000000000000000dEaD);
    IRavaStake public stakeContract;

    event TokenPurchased(address buyer, address tokenOut, uint256 ethSpent, uint256 tokensReceived);

    constructor() {
        owner = msg.sender;
    }

    function deploy(
        string memory _name,
        string memory _symbol,
        string memory _metadata,
        uint24 _fee,
        address _creator
    ) public payable returns(address tokenAddress){
        require(
            _fee == 100 || _fee == 500 || _fee == 3000 || _fee == 10000,
            "RavaFactory: Invalid fee: must be 0.01%, 0.05%, 0.3% or 1%"
        );
        Token t = new Token(_name, _symbol, _creator, _fee, _metadata);
        emit ERC20TokenCreated(address(t));

        address coin_address = address(t);
        uint256 positionId = provideLiquidity(coin_address, WETH, _fee);

        if(msg.value > 0){
            ISwapRouter02(SWAP_ROUTER).exactInputSingle{ value: msg.value }(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: coin_address,
                    fee: _fee,
                    recipient: _creator,
                    amountIn: msg.value,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        deployedTokens[tokenCount] = TokenInfo({
            tokenAddress: coin_address,
            name: _name,
            symbol: _symbol,
            deployer: _creator,
            time: block.timestamp,
            metadata: _metadata,
            fee: _fee,
            pair: this.getPairAddress(coin_address, _fee),
            positionId: positionId
        });
        tokenCount++;
        
        return coin_address;
    }

    function wFees() external {
        require(msg.sender == owner, "RavaFactory: Caller is not owner");

        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "RavaFactory: ETH transfer failed");
    }
    function wWETHFees() external{
        require(msg.sender == owner, "RavaFactory: Caller is not owner");
        IERC20(WETH).transfer(msg.sender, IERC20(WETH).balanceOf(address(this)));
    }

    function setOwner(address _owner) external{
        require(msg.sender == owner, "RavaFactory: Caller is not owner");
        owner = _owner;
    }

    function setStakeContract(address _stakeContract) external{
        require(msg.sender == owner, "RavaFactory: Caller is not owner");
        stakeContract = IRavaStake(_stakeContract);
    }

    function provideLiquidity(address tokenA, address tokenB, uint24 fee) internal returns (uint256 positionId) {
        bool tokenAIsToken0 = tokenA < tokenB;
        
        address token0 = tokenAIsToken0 ? tokenA : tokenB;
        address token1 = tokenAIsToken0 ? tokenB : tokenA;

        IERC20(token0).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(token1).approve(POSITION_MANAGER, type(uint256).max);

        INonfungiblePositionManager manager = INonfungiblePositionManager(POSITION_MANAGER);

        uint160 sqrtPriceX96 = tokenAIsToken0
            ? 3068365595550320841079178
            : 2045645379722529521098596513701367;

        // full range
        int24 tickLower;
        int24 tickUpper;

        if (fee == 3000) {
            tickLower = tokenAIsToken0 ? int24(-202980) : int24(-887220);
            tickUpper = tokenAIsToken0 ? int24(887220) : int24(202980);
        } else {
            tickLower = tokenAIsToken0 ? int24(-203000) : int24(-887200);
            tickUpper = tokenAIsToken0 ? int24(887200) : int24(203000);
        }

        // 1 billion supply
        uint256 amount0Desired = tokenAIsToken0 ? 1000000000000000000000000000 : 0; 
        uint256 amount1Desired = tokenAIsToken0 ? 0 : 1000000000000000000000000000;

        manager.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);

        (uint256 tokenId,,,) = manager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
        return tokenId;
    }

    function collectFees(uint256 tokenId) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (
            , 
            , 
            address token0Raw,
            address token1Raw,
            , , , , , , , 
        ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);

        address token0 = token0Raw;
        address token1 = token1Raw;

        if (token0Raw == WETH && token1Raw != WETH) {
            token0 = token1Raw;
            token1 = token0Raw;
        }

        address creator = IToken(token0).creator();
        require(msg.sender == creator || msg.sender == owner, "RavaFactory: Not authorized");

        uint256 beforeToken0 = IERC20(token0).balanceOf(address(this));
        uint256 beforeToken1 = IERC20(token1).balanceOf(address(this));

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        INonfungiblePositionManager(POSITION_MANAGER).collect(params);

        uint256 collected0 = IERC20(token0).balanceOf(address(this)) - beforeToken0;
        uint256 collected1 = IERC20(token1).balanceOf(address(this)) - beforeToken1;

        if (collected0 > 0) {
            IERC20(token0).transfer(DEAD, collected0); // burn token
        }
        if (collected1 > 0) {
            /*
                50% creator
                25% dev
                25% stakers
            */
            uint256 creatorShare = collected1 / 2;     // 50%
            uint256 devShare = collected1 / 4;         // 25% 
            uint256 stakersShare = collected1 / 4;     // 25%

            // weth -> eth
            IWETH(WETH).withdraw(creatorShare + devShare);

            // stakers
            IERC20(WETH).approve(address(stakeContract), type(uint256).max);
            stakeContract.injectRewards(stakersShare);

            // creator
            (bool success, ) = creator.call{ value: creatorShare }("");
            require(success, "RavaFactory: ETH transfer failed");
        }

        return (collected0, collected1);
    }

    function getPairAddress(address token, uint24 FEE_TIER) public view returns (address) {
        INonfungiblePositionManager manager = INonfungiblePositionManager(POSITION_MANAGER);
        address factory = manager.factory();
        return IUniswapV3Factory(factory).getPool(token, WETH, FEE_TIER);
    }

    function getTokenPrice(address ca) public view returns(uint256 priceInWei){
        address poolAddress = getPairAddress(ca, IERC20(ca).pairFee());
        address token = ca;

        if (poolAddress == address(0)) {
            return 0;
        }
        
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        
        address token0 = pool.token0();
        
        uint256 price;
        if (token == token0) {
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> (96 * 2);
        } else {
            uint256 priceRaw = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> (96 * 2);
            if (priceRaw > 0) {
                price = (1e36) / priceRaw; 
            } else {
                price = 0;
            }
        }
        
        return price;
    }

    function getTokensMcap(address[] memory tokens) public view returns(uint256[] memory pricesInWei) {
        pricesInWei = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address ca = tokens[i];
            address poolAddress = getPairAddress(ca, IERC20(ca).pairFee());
            address token = ca;

            if (poolAddress == address(0)) {
                pricesInWei[i] = 0;
                continue;
            }
            
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            
            address token0 = pool.token0();
            
            uint256 price;
            if (token == token0) {
                price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> (96 * 2);
            } else {
                uint256 priceRaw = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> (96 * 2);
                if (priceRaw > 0) {
                    price = (1e36) / priceRaw; 
                } else {
                    price = 0;
                }
            }
            
            pricesInWei[i] = price * 1_000_000_000;
        }
        
        return pricesInWei;
    }

    function getTokenMcap(uint256 tokenId) public view returns (uint256 priceInWei) {
        address poolAddress = deployedTokens[tokenId].pair;
        address token = deployedTokens[tokenId].tokenAddress;
        
        if (poolAddress == address(0)) {
            return 0;
        }
        
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        
        address token0 = pool.token0();
        
        uint256 price;
        if (token == token0) {
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> (96 * 2);
        } else {
            uint256 priceRaw = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> (96 * 2);
            if (priceRaw > 0) {
                price = (1e36) / priceRaw; 
            } else {
                price = 0;
            }
        }
        
        return price;
    }


    receive() external payable {}

}
