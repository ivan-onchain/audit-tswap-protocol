// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18);
        assertEq(weth.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;

        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        assert(weth.balanceOf(user) >= expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }

    function test_getInputAmountBasedOnOutput() public{
        vm.startPrank(user);
        uint256 outputAmount = 10e18;
        uint256 inputReserves = 100e18;
        uint256 outputReserves = 200e18;
        uint256 inputAmount = pool.getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);
        vm.stopPrank();

        uint256 expectedWrongInputAmount = ((inputReserves * outputAmount) * 1_000) /
            ((outputReserves - outputAmount) * 997);
        // Some math here: 
        // expectedInputAmount = 100e18*10e18 * 1_000 / 200e18 - 10e18 * 997 
        // expectedInputAmount = 1_000_000e18 / 190e18 * 997 = 1_000_000e18/189430e18
        // expectedInputAmount = 5.278994879374967006e18 but what actually is returning is 52.78994879374967006e18
        // ten times more than the expected value.
        expectedWrongInputAmount = 52789948793749670062;
        assertEq(inputAmount, expectedWrongInputAmount);
    }

      function test_noSlippageProtectionInSwapExactOutput() public{

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        address whale = makeAddr("WHALE");
        poolToken.mint(whale, 100e18);
        console.log('address(poolToken): ', address(poolToken));
        console.log('address(weth): ', address(weth));
        
        uint256 poolTokenPrice = pool.getPriceOfOnePoolTokenInWeth();
        uint256 wethPrice = pool.getPriceOfOneWethInPoolTokens();
        console.log('poolTokenPrice: ', poolTokenPrice);
        // 1 weth --> 0,987158034397061298 pool Token
        console.log('wethPrice: ', wethPrice);
        // 1 pool token --> 0,987158034397061298 weth
        
        vm.startPrank(whale);
        poolToken.approve(address(pool), type(uint256).max);
        uint256 poolTokenBalance = poolToken.balanceOf(whale);
        console.log('poolTokenBalance: ', poolTokenBalance);
        pool.swapExactOutput(poolToken, weth, 40e18, uint64(block.timestamp));
        vm.stopPrank();
        assertEq(weth.balanceOf(whale), 40e18);

        poolToken.mint(user, 90e18);
        vm.startPrank(user);
        uint256 initialUserBalance = poolToken.balanceOf(user);
        console.log('initialUserBalance: ', initialUserBalance);
        poolToken.approve(address(pool), type(uint256).max);
        // User hopes to pay 0.987158034397061298 poolToken for 1 weth
        pool.swapExactOutput(poolToken, weth, 1e18, uint64(block.timestamp));
        uint256 finalUserBalance = poolToken.balanceOf(user);

        uint256 actualAmountPayByUser = initialUserBalance - finalUserBalance;
        console.log('actualAmountPayByUser: ', actualAmountPayByUser);
        // actualAmountPayByUser --> 2.836769094947264087
        // But at the end user paid much more of what he though
        assertEq(actualAmountPayByUser, 2836769094947264087);
        vm.stopPrank();
    }

}
