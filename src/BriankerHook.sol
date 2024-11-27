// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Briankerc20} from "./Briankerc20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

contract Brianker is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 lock) public s_lockers;
    uint24 fee = 3000;
    int24 TICK_SPACING = 60;
    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    uint nonce;


    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


    function launchTokenWithTimeLock(string memory name, string memory symbol) public {
        address deployedToken = deployWithCreate2(name, symbol);
        
        // initialize a poolkey with 
        PoolKey memory poolkey = PoolKey({
            currency0: Currency.wrap(deployedToken),
            currency1: Currency.wrap(address(0)),
            fee: fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
        uint256 totalSupply = 1_000_000e18;
    
        uint256 ethAmount = 0.00001 ether; 

        uint256 priceX96 = (totalSupply * (2**96)) / ethAmount;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(priceX96)); 
        poolManager.initialize(poolkey, sqrtPriceX96);
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

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        
        return (BaseHook.afterSwap.selector, );
    }

}

