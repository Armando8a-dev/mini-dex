// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/MiniDEX.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// ─── Mocks ────────────────────────────────────────────────────────────────────

contract MockToken is ERC20 {
    constructor(string memory s) ERC20(s, s) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev LP token mock — mintable, with reserves for getReserves
contract MockPair is ERC20 {
    uint112 public reserve0;
    uint112 public reserve1;

    constructor() ERC20("LP", "LP") {}

    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function burn(address from, uint256 amount) external { _burn(from, amount); }

    function setReserves(uint112 r0, uint112 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }
}

contract MockFactory {
    address public pair;
    constructor(address _pair) { pair = _pair; }
    function getPair(address, address) external view returns (address) { return pair; }
}

/// @dev Router: mints LP on addLiquidity, burns LP and sends tokens on removeLiquidity
contract MockRouter {
    MockPair public lp;

    constructor(MockPair _lp) { lp = _lp; }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256, uint256, uint256 liquidity) {
        // Use 99% of desired to simulate Uniswap rounding (leaves 1% unused)
        uint256 usedA = (amountADesired * 99) / 100;
        uint256 usedB = (amountBDesired * 99) / 100;
        liquidity = (usedA + usedB) / 2;

        lp.mint(to, liquidity);

        // Update reserves
        uint112 r0 = uint112(lp.reserve0() + usedA);
        uint112 r1 = uint112(lp.reserve1() + usedB);
        lp.setReserves(r0, r1);

        return (usedA, usedB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB) {
        amountA = liquidity;
        amountB = liquidity;

        lp.burn(msg.sender, liquidity);

        MockToken(tokenA).mint(to, amountA);
        MockToken(tokenB).mint(to, amountB);
    }
}

// ─── Test ─────────────────────────────────────────────────────────────────────

contract MiniDEXTest is Test {
    MiniDEX public dex;
    MockPair public lp;
    MockFactory public mockFactory;
    MockRouter public mockRouter;
    MockToken public tokenA;
    MockToken public tokenB;

    address user = address(0x1);
    address stranger = address(0x99);

    uint256 constant AMOUNT = 1000 ether;
    uint256 constant DEADLINE = type(uint256).max;
    uint256 constant SLIPPAGE = 100; // 1%

    function setUp() public {
        tokenA = new MockToken("TokenA");
        tokenB = new MockToken("TokenB");
        lp = new MockPair();
        lp.setReserves(1_000_000 ether, 1_000_000 ether);

        mockRouter = new MockRouter(lp);
        mockFactory = new MockFactory(address(lp));

        dex = new MiniDEX(address(mockRouter), address(mockFactory));

        tokenA.mint(user, AMOUNT * 10);
        tokenB.mint(user, AMOUNT * 10);

        vm.startPrank(user);
        tokenA.approve(address(dex), type(uint256).max);
        tokenB.approve(address(dex), type(uint256).max);
        vm.stopPrank();
    }

    // ─── constructor ──────────────────────────────────────────────────────────

    function test_constructor_setsAddresses() public view {
        assertEq(dex.router(), address(mockRouter));
        assertEq(dex.factory(), address(mockFactory));
    }

    function test_constructor_revertsZeroRouter() public {
        vm.expectRevert(MiniDEX.ZeroAddress.selector);
        new MiniDEX(address(0), address(mockFactory));
    }

    function test_constructor_revertsZeroFactory() public {
        vm.expectRevert(MiniDEX.ZeroAddress.selector);
        new MiniDEX(address(mockRouter), address(0));
    }

    // ─── deposit ──────────────────────────────────────────────────────────────

    function test_deposit_creditsPosToUser() public {
        vm.prank(user);
        uint256 lps = dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);

        assertEq(dex.positions(user, address(tokenA), address(tokenB)), lps);
        assertGt(lps, 0);
    }

    function test_deposit_returnsUnusedTokens() public {
        uint256 balABefore = tokenA.balanceOf(user);
        uint256 balBBefore = tokenB.balanceOf(user);

        vm.prank(user);
        dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);

        // router uses 99% → 1% returned
        uint256 returned = AMOUNT / 100;
        assertApproxEqAbs(tokenA.balanceOf(user), balABefore - AMOUNT + returned, 1);
        assertApproxEqAbs(tokenB.balanceOf(user), balBBefore - AMOUNT + returned, 1);
    }

    function test_deposit_emitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit MiniDEX.LiquidityAdded(user, address(tokenA), address(tokenB), 0, 0, 0);

        vm.prank(user);
        dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);
    }

    function test_deposit_accumulates() public {
        vm.startPrank(user);
        uint256 lp1 = dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);
        uint256 lp2 = dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);
        vm.stopPrank();

        assertEq(dex.positions(user, address(tokenA), address(tokenB)), lp1 + lp2);
    }

    function test_deposit_revertsIfZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(MiniDEX.ZeroAmount.selector);
        dex.deposit(address(tokenA), address(tokenB), 0, AMOUNT, SLIPPAGE, DEADLINE);
    }

    function test_deposit_revertsIfDeadlineExpired() public {
        vm.warp(1000);
        vm.prank(user);
        vm.expectRevert(MiniDEX.DeadlineExpired.selector);
        dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, 999);
    }

    // ─── withdraw ─────────────────────────────────────────────────────────────

    function _deposit() internal returns (uint256 lpTokens) {
        vm.prank(user);
        lpTokens = dex.deposit(address(tokenA), address(tokenB), AMOUNT, AMOUNT, SLIPPAGE, DEADLINE);
    }

    function test_withdraw_reducesPosition() public {
        uint256 lps = _deposit();

        vm.prank(user);
        dex.withdraw(address(tokenA), address(tokenB), lps, SLIPPAGE, DEADLINE);

        assertEq(dex.positions(user, address(tokenA), address(tokenB)), 0);
    }

    function test_withdraw_sendsTokensToUser() public {
        uint256 lps = _deposit();
        uint256 balABefore = tokenA.balanceOf(user);

        vm.prank(user);
        dex.withdraw(address(tokenA), address(tokenB), lps, SLIPPAGE, DEADLINE);

        assertGt(tokenA.balanceOf(user), balABefore);
    }

    function test_withdraw_emitsEvent() public {
        uint256 lps = _deposit();

        vm.expectEmit(true, true, true, false);
        emit MiniDEX.LiquidityRemoved(user, address(tokenA), address(tokenB), 0, 0, 0);

        vm.prank(user);
        dex.withdraw(address(tokenA), address(tokenB), lps, SLIPPAGE, DEADLINE);
    }

    function test_withdraw_partialWithdraw() public {
        uint256 lps = _deposit();

        vm.prank(user);
        dex.withdraw(address(tokenA), address(tokenB), lps / 2, SLIPPAGE, DEADLINE);

        assertEq(dex.positions(user, address(tokenA), address(tokenB)), lps - lps / 2);
    }

    function test_withdraw_revertsIfInsufficientPosition() public {
        uint256 lps = _deposit();

        vm.prank(user);
        vm.expectRevert(MiniDEX.InsufficientPosition.selector);
        dex.withdraw(address(tokenA), address(tokenB), lps + 1, SLIPPAGE, DEADLINE);
    }

    function test_withdraw_revertsIfZeroAmount() public {
        _deposit();
        vm.prank(user);
        vm.expectRevert(MiniDEX.ZeroAmount.selector);
        dex.withdraw(address(tokenA), address(tokenB), 0, SLIPPAGE, DEADLINE);
    }

    function test_withdraw_revertsIfDeadlineExpired() public {
        uint256 lps = _deposit();
        vm.warp(1000);
        vm.prank(user);
        vm.expectRevert(MiniDEX.DeadlineExpired.selector);
        dex.withdraw(address(tokenA), address(tokenB), lps, SLIPPAGE, 999);
    }

    // ─── getPosition ──────────────────────────────────────────────────────────

    function test_getPosition_returnsZeroIfNone() public view {
        assertEq(dex.getPosition(stranger, address(tokenA), address(tokenB)), 0);
    }

    function test_getPosition_returnsCorrectAfterDeposit() public {
        uint256 lps = _deposit();
        assertEq(dex.getPosition(user, address(tokenA), address(tokenB)), lps);
    }

    // ─── getPoolShareBps ──────────────────────────────────────────────────────

    function test_getPoolShareBps_returnsZeroIfNoPair() public {
        MockFactory emptyFactory = new MockFactory(address(0));
        MiniDEX emptyDex = new MiniDEX(address(mockRouter), address(emptyFactory));
        assertEq(emptyDex.getPoolShareBps(user, address(tokenA), address(tokenB)), 0);
    }

    function test_getPoolShareBps_nonZeroAfterDeposit() public {
        _deposit();
        uint256 share = dex.getPoolShareBps(user, address(tokenA), address(tokenB));
        assertGt(share, 0);
    }

    // ─── fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_deposit_positionAlwaysNonZero(uint256 amount) public {
        amount = bound(amount, 1 ether, 500 ether);

        tokenA.mint(user, amount);
        tokenB.mint(user, amount);

        vm.prank(user);
        uint256 lps = dex.deposit(address(tokenA), address(tokenB), amount, amount, SLIPPAGE, DEADLINE);

        assertGt(lps, 0);
        assertEq(dex.positions(user, address(tokenA), address(tokenB)), lps);
    }
}
