// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BriankerHook} from "../src/BriankerHook.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ContractConstants} from "./lib/live_contracts.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";


contract BriankerHookDeployer is Script{
    using ContractConstants for *;


    function run() public {
        
        
          
        ///////////////////////////
        //  D E P L O Y H O O K  //
        ///////////////////////////
        uint160 flags = 
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            ContractConstants.POOL_MANAGER, 
            ContractConstants.POSITION_MANAGER, 
            ContractConstants.PERMIT2, 
            ContractConstants.STATE_VIEW
        );

        (address hookAddress, bytes32 salt) =
            HookMiner.find(ContractConstants.CREATE2_DEPLOYER, flags, type(BriankerHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        BriankerHook briankerHook = new BriankerHook{salt: salt}(IPoolManager(ContractConstants.POOL_MANAGER), PositionManager(payable(ContractConstants.POSITION_MANAGER)), ContractConstants.PERMIT2, ContractConstants.STATE_VIEW);
        require(address(briankerHook) == hookAddress, "CounterScript: hook address mismatch");
        console.log("Contract deployed via CREATE2_DEPLOYER at: ", address(briankerHook));


        ///////////////////////////
        // C R E A T E   E R C   //
        ///////////////////////////

        string memory name = "Test";
        string memory symbol = "TST";
        uint256 startTime = block.timestamp - 1;
        uint256 ethAmount = 1e10;


        vm.broadcast();
        address deployedToken = briankerHook.launchTokenWithTimeLock{value: ethAmount}(name, symbol, startTime);


        PoolSwapTest swapRouter = PoolSwapTest(ContractConstants.POOL_SWAP_TEST);

        // slippage tolerance to allow for unlimited price impact
        uint160  MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
        uint160  MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

        address token0 = address(0);
        address token1 = address(deployedToken);
        address hookAddr = address(briankerHook);

        PoolKey memory poolkey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

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
        
        string[] memory commands = new string[](2);

        vm.startBroadcast();
        swapRouter.swap{value: 1e15}(poolkey, params, testSettings, hookData);
        vm.stopBroadcast();

        console.log("Hook contract deployed at: ", deployedToken);
    }
}



