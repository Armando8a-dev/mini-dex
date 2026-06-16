// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2.sol";

/// @title MiniDEX — Liquidity vault manager on top of Uniswap V2
/// @notice Deposit token pairs to add liquidity. LP tokens are held by the vault
///         and credited to users. Withdraw at any time with BPS slippage protection.
contract MiniDEX is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable factory;

    uint256 public constant BPS_BASE = 10_000;

    // user => tokenA => tokenB => LP tokens deposited through this vault
    mapping(address => mapping(address => mapping(address => uint256))) public positions;

    event LiquidityAdded(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 lpTokens
    );
    event LiquidityRemoved(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 lpTokens
    );

    error ZeroAmount();
    error InvalidPair();
    error InsufficientPosition();
    error DeadlineExpired();
    error ZeroAddress();

    constructor(address _router, address _factory) {
        if (_router == address(0) || _factory == address(0)) revert ZeroAddress();
        router = _router;
        factory = _factory;
    }

    /// @notice Add liquidity to a Uniswap V2 pair. LP tokens held in vault.
    /// @param maxSlippageBps  Max slippage vs desired amounts (e.g. 50 = 0.5%)
    function deposit(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external nonReentrant returns (uint256 lpTokens) {
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();

        uint256 amountAMin = amountADesired - (amountADesired * maxSlippageBps / BPS_BASE);
        uint256 amountBMin = amountBDesired - (amountBDesired * maxSlippageBps / BPS_BASE);

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

        IERC20(tokenA).approve(router, amountADesired);
        IERC20(tokenB).approve(router, amountBDesired);

        (uint256 usedA, uint256 usedB, uint256 lp) = IV2Router(router).addLiquidity(
            tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, address(this), deadline
        );

        // Return unused tokens to user
        if (amountADesired > usedA) IERC20(tokenA).safeTransfer(msg.sender, amountADesired - usedA);
        if (amountBDesired > usedB) IERC20(tokenB).safeTransfer(msg.sender, amountBDesired - usedB);

        lpTokens = lp;
        positions[msg.sender][tokenA][tokenB] += lp;

        emit LiquidityAdded(msg.sender, tokenA, tokenB, usedA, usedB, lp);
    }

    /// @notice Withdraw LP tokens from vault and remove liquidity from Uniswap.
    /// @param lpAmount  Amount of LP tokens to redeem (must be <= user's position)
    function withdraw(
        address tokenA,
        address tokenB,
        uint256 lpAmount,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (lpAmount == 0) revert ZeroAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (positions[msg.sender][tokenA][tokenB] < lpAmount) revert InsufficientPosition();

        address pair = IFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) revert InvalidPair();

        // Compute minAmounts from current reserves proportional to lpAmount
        (uint256 minA, uint256 minB) = _minAmounts(pair, tokenA, tokenB, lpAmount, maxSlippageBps);

        // CEI: update position before external calls
        positions[msg.sender][tokenA][tokenB] -= lpAmount;

        IPair(pair).approve(router, lpAmount);
        (amountA, amountB) = IV2Router(router).removeLiquidity(
            tokenA, tokenB, lpAmount, minA, minB, msg.sender, deadline
        );

        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, lpAmount);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Returns user's LP position for a pair (order-independent).
    function getPosition(address user, address tokenA, address tokenB) external view returns (uint256) {
        uint256 pos = positions[user][tokenA][tokenB];
        if (pos == 0) return positions[user][tokenB][tokenA];
        return pos;
    }

    /// @notice Returns the user's share of the pool in BPS (10_000 = 100%).
    function getPoolShareBps(address user, address tokenA, address tokenB) external view returns (uint256) {
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) return 0;
        uint256 totalLp = IPair(pair).totalSupply();
        if (totalLp == 0) return 0;
        uint256 userLp = positions[user][tokenA][tokenB];
        return (userLp * BPS_BASE) / totalLp;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _minAmounts(address pair, address tokenA, address tokenB, uint256 lpAmount, uint256 slippageBps)
        internal
        view
        returns (uint256 minA, uint256 minB)
    {
        uint256 totalLp = IPair(pair).totalSupply();
        (uint112 r0, uint112 r1,) = IPair(pair).getReserves();

        // Determine which reserve corresponds to tokenA
        // Uniswap stores token0 < token1 by address sort
        (uint256 reserveA, uint256 reserveB) =
            tokenA < tokenB ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        uint256 expectedA = (reserveA * lpAmount) / totalLp;
        uint256 expectedB = (reserveB * lpAmount) / totalLp;

        minA = expectedA - (expectedA * slippageBps / BPS_BASE);
        minB = expectedB - (expectedB * slippageBps / BPS_BASE);
    }
}
