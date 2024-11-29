// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BriankerHook} from "../src/BriankerHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateView} from "v4-periphery/src/lens/StateView.sol";


contract BriankerHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    BriankerHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    uint24 public constant  fee = 3000; 
    int24 public constant   TICK_SPACING = 60;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, posm, permit2); 
        deployCodeTo("BriankerHook.sol:BriankerHook", constructorArgs, flags);
        hook = BriankerHook(flags);
    }

    function testFactory() public {
        // Setup values
        string memory name = "Test";
        string memory symbol = "TST";
        uint256 startTime = block.timestamp + 1 days;
        uint256 ethAmount = 1e10;

        // Call function with required ETH value
        vm.deal(address(this), ethAmount);
        address deployedToken = hook.launchTokenWithTimeLock{value: ethAmount}(name, symbol, startTime);
        
        // assert all the tokens are used in the pool 
        assertEq(IERC20(deployedToken).balanceOf(address(hook)), 0);

      

        PoolKey memory poolkey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(deployedToken),
            fee: fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        PoolId poolId = poolkey.toId();
        
        
 
        // Get current price from pool
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);

        // Calculate the raw price
        uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);
        
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Raw tokens you get for 1 ETH:", price);

        

        // slippage tolerance to allow for unlimited price impact
        uint160  MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
        uint160  MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

        address token0 = address(0);
        address token1 = address(deployedToken);
        address hookAddr = address(hook);

        vm.deal(address(this), 1e15);
        
        vm.warp(block.timestamp + 10 days);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);

        bool zeroForOne = true;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -1e15,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        bytes memory hookData = new bytes(0); // no hook data on the hookless pool
        
        swapRouter.swap{value: 1e15}(poolkey, params, testSettings, hookData);

    }


    

}
