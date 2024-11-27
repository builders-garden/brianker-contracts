// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Briankerc20} from "./Briankerc20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";


contract Brianker is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 lock) public s_lockers;
    uint24 public constant  fee = 3000; 
    int24 public constant   TICK_SPACING = 60;
    int24 public constant   MIN_TICK = -91020;

    int24 internal constant MAX_TICK = 887220;

    uint internal nonce;
    uint internal fixedERC20Supply = 1_000_000e18;


    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


    function launchTokenWithTimeLock(string memory name, string memory symbol) public payable {
        uint256 ethAmount = 0.00001 ether; 
        require(msg.value == ethAmount, "Brianker Hook: not enough ether sent to initialize a pool");
        
        // Deploy token and approve pool manager
        address deployedToken = deployWithCreate2(name, symbol);
        Briankerc20(deployedToken).approve(address(poolManager), fixedERC20Supply);
        
        PoolKey memory poolkey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(deployedToken),
            fee: fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });

        // Calculate initial sqrt price
        uint256 ethScaled = ethAmount * (2**96);
        uint256 priceX96 = ethScaled / fixedERC20Supply;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(priceX96));

        // Initialize pool
        poolManager.initialize(poolkey, sqrtPriceX96);

        // Calculate optimal liquidity amount using LiquidityAmounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            ethAmount,
            fixedERC20Supply
        );

        // Add initial liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: int256(uint256(liquidity)), 
            salt: bytes32(0)
        });


        Briankerc20(deployedToken).approve(address(poolManager), fixedERC20Supply);
        poolManager.settle{value: ethAmount}();
        poolManager.modifyLiquidity(poolkey, params, "");
        poolManager.unlock("");
    }


    function deployWithCreate2(
        string memory name,
        string memory symbol
    ) internal returns (address token) {
        // Get creation bytecode and encode constructor args
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Briankerc20).creationCode,
            abi.encode(name, symbol)
        );
        
        // Use nonce directly as salt
        bytes32 salt = bytes32(nonce);
        
        assembly {
            token := create2(
                0,                          // no ETH sent
                add(bytecodeWithArgs, 0x20),
                mload(bytecodeWithArgs),    
                salt                        // nonce as salt
            )
            
            if iszero(extcodesize(token)) {
                revert(0, 0)
            }
        }
        nonce++;
    }



    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        require(sender == address(this), "Brianker Hook: not allowed to add liquidity");

        return BaseHook.beforeAddLiquidity.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 > 0) {  // ETH fees
            uint256 feeAmount0 = uint256(uint128(amount0)) * fee / 1_000_000;
            poolManager.take(key.currency0, address(this), feeAmount0);
        }

        if (amount1 > 0) {  // Token fees
            uint256 feeAmount1 = uint256(uint128(amount1)) * fee / 1_000_000;
            poolManager.take(key.currency1, address(this), feeAmount1);
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        require(s_lockers[key.toId()] < block.timestamp, "Brianker: This pool isn't open for trades yet!");

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}

