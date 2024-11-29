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
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";

import "forge-std/Test.sol";
contract BriankerHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------


    event TokenDeployed(address deployedERC20Contract);

    mapping(PoolId => uint256 lock) public s_lockers;
    uint24 public constant  fee = 3000; 
    int24 public constant   TICK_SPACING = 60;
    int24 public constant   MIN_TICK = -887220;

    int24 internal constant MAX_TICK = 887220;

    uint internal nonce;
    uint internal fixedERC20Supply = 1_000_000e18;

    uint160 sqrtPriceX96 = 792281625142643375935439503367252323;

    PositionManager posm;
    address permit2;

    constructor(IPoolManager _poolManager, PositionManager _positionManager, address _permit2) BaseHook(_poolManager) {
        posm = _positionManager;
        permit2 = _permit2;
    }

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


    function launchTokenWithTimeLock(string memory name, string memory symbol, uint startTime) public payable returns(address deployedToken) {
        uint256 ethAmount = 1e10; 
        require(msg.value == ethAmount, "Brianker Hook: not enough ether sent to initialize a pool");
        
 

        // Deploy token and approve pool manager
        deployedToken = deployWithCreate2(name, symbol, fixedERC20Supply);
        
        PoolKey memory poolkey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(deployedToken),
            fee: fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
        s_lockers[poolkey.toId()] = startTime;
       
       
       
        // Calculate optimal liquidity amount using LiquidityAmounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(MIN_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            ethAmount,
            fixedERC20Supply
        );

        bytes[] memory params = new bytes[](1);
        
        poolManager.initialize(poolkey, sqrtPriceX96);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory mintParams = new bytes[](2);
        mintParams[0] = abi.encode(poolkey, MIN_TICK, MAX_TICK, liquidity, ethAmount, fixedERC20Supply, address(this), abi.encode(address(this)));
        mintParams[1] = abi.encode(poolkey.currency0, poolkey.currency1);

        uint256 deadline = block.timestamp;
        params[0] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), deadline
        );

        Briankerc20(deployedToken).approve(address(permit2), type(uint256).max);

  
        IAllowanceTransfer(address(permit2)).approve(deployedToken, address(posm), type(uint160).max, type(uint48).max);
        
        emit TokenDeployed(deployedToken);

        posm.multicall{value:  1e10 }(params);
    }


    function deployWithCreate2(
        string memory name,
        string memory symbol,
        uint totalSupply
    ) internal returns (address token) {
        // Get creation bytecode and encode constructor args
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Briankerc20).creationCode,
            abi.encode(name, symbol, fixedERC20Supply)
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
        address sender, //   <-- bad design ? this is posm in that case passing via multicall .-. 
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookdata
    ) external override returns (bytes4) {
        address preMulticallSender = abi.decode(hookdata, (address));
        require(preMulticallSender == address(this) && sender == address(posm), "Brianker Hook: not allowed to add liquidity");

        return BaseHook.beforeAddLiquidity.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // int128 amount0 = delta.amount0();
        // int128 amount1 = delta.amount1();

        // if (amount0 > 0) {  // ETH fees
        //     uint256 feeAmount0 = uint256(uint128(amount0)) * fee / 1_000_000;
        //     poolManager.take(key.currency0, address(this), feeAmount0);
        // }

        // if (amount1 > 0) {  // Token fees
        //     uint256 feeAmount1 = uint256(uint128(amount1)) * fee / 1_000_000;
        //     poolManager.take(key.currency1, address(this), feeAmount1);
        // }
        
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

