// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant{
    ERC20Mock poolToken;
    ERC20Mock weth;
    PoolFactory factory;
    TSwapPool pool;
    Handler handler;
   

    int256 constant STARTING_X = 100e18;
    int256 constant STARTING_Y = 50e18;


   function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

        poolToken.mint(address(this), uint256(STARTING_X));
        weth.mint(address(this), uint256(STARTING_Y));

        poolToken.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);

        pool.deposit(
            uint256(STARTING_Y), 
            uint256(STARTING_Y),
            uint256(STARTING_X),
            uint64(block.timestamp)
        );

        handler = new Handler(pool);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.swapPoolTokenForWethBasedOnOutputWeth.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

   }

   function statefulFuzz_constantProductFormulaStaysTheSame() public view {
       assert(handler.actualDeltaX() == handler.expectedDeltaX());
   } 
}