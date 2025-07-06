# RavaFinance 🚀

**Decentralized Token Factory & Liquidity Management Protocol**

RavaFinance is a DeFi protocol that enables users to easily create ERC20 tokens and automatically provide liquidity on Uniswap V3.

## 🌟 Features

### Token Factory
- **Instant Token Creation**: Deploy ERC20 tokens in a single transaction
- **Customizable Fee Structure**: Choose from 0.01%, 0.05%, 0.3%, or 1% fee tiers
- **Metadata Support**: Rich metadata support for tokens
- **Automatic LP Creation**: Full-range liquidity positions created automatically

### Uniswap V3 Integration
- **Auto Pool Creation**: Automatic pool initialization with optimal pricing
- **Full-Range Positions**: Maximum liquidity coverage with full-range LP positions
- **Fee Collection**: Automated trading fee collection and distribution system
- **Price Tracking**: Real-time token price and market cap calculations

### Revenue Distribution Model
Trading fees are distributed as follows:
- 🎯 **50%** → Token Creator
- 🏗️ **25%** → Development Team  
- 💰 **25%** → Stakers (via staking contract)

## 📋 Smart Contract Overview

### Core Functions

**`deploy()`** - Create new ERC20 token with automatic Uniswap V3 liquidity
```solidity
function deploy(
    string memory _name,
    string memory _symbol, 
    string memory _metadata,
    uint24 _fee,
    address _creator
) public payable returns(address tokenAddress)
```

**`collectFees()`** - Collect and distribute trading fees from LP positions
```solidity
function collectFees(uint256 tokenId) external nonReentrant
```

**`getTokenPrice()`** - Get real-time token price in Wei
```solidity
function getTokenPrice(address ca) public view returns(uint256 priceInWei)
```

### Key Components

- **Position Manager**: Uniswap V3 NFT Position Manager integration
- **Swap Router**: Uniswap V3 SwapRouter02 for token purchases
- **Price Oracle**: Real-time price feeds from Uniswap V3 pools
- **Staking Integration**: Automatic reward injection to staking contract

## 🔧 Technical Specifications

### Supported Networks
- **Ethereum Mainnet** (Primary deployment)

### Dependencies
- OpenZeppelin ReentrancyGuard
- Uniswap V3 Core & Periphery contracts
- Custom ERC20 implementation

### Key Addresses
```solidity
POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
```

## 📊 Token Deployment Flow

1. **Create Token**: Deploy ERC20 with custom parameters
2. **Initialize Pool**: Create Uniswap V3 pool with optimal pricing  
3. **Add Liquidity**: Provide full-range liquidity (1B tokens)
4. **Enable Trading**: Token immediately tradeable on Uniswap
5. **Fee Collection**: Automated fee collection and distribution

## 🔒 Security Features

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Access Control**: Owner-only functions for critical operations
- **Input Validation**: Strict validation for fee tiers and parameters
- **Dead Address Burning**: Token fees automatically burned to dead address

## 🌐 Links

- **Website**: https://rava.finance
- **Twitter**: https://x.com/RavaFinance  
- **Telegram**: https://t.me/RavaFinance
