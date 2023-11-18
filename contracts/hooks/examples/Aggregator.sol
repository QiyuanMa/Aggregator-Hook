// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {FeeLibrary} from "@uniswap/v4-core/contracts/libraries/FeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {BaseHook} from "../../BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {ILockCallback} from "@uniswap/v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import {D3Maker} from "./D3Maker.sol";
import "forge-std/Test.sol";

import "../../libraries/LiquidityAmounts.sol";
import "./D3Maker.sol";

contract AggregatorHook is BaseHook, ILockCallback, D3Maker {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using FeeLibrary for uint24;

    error SenderMustBeHook();

    bytes internal constant ZERO_BYTES = bytes("");

    int24 public tickLower;
    int24 public tickUpper;
    int24 public tickMid;

    // record deposited into uni
    // todo maybe not necessary
    mapping(address => uint256) public depositedInPoolManager; 

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false
        });
    }

    // Only for mocking
    // function setTicks(int24 current, int24 lower, int24 upper) public {
    //     currentTick = current;
    //     lowerTick = lower;
    //     upperTick = upper;
    // }

    function removeRemainingLiquidity(PoolKey calldata key) external {
        console.log("\n========= removeRemainingLiquidity ==========");
        PoolId poolId = key.toId();
        uint128 liquidity = poolManager.getLiquidity(poolId);

        _modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: -tickUpper,
                tickUpper: -tickLower, 
                liquidityDelta: -int128(liquidity)
            })
        );

        liquidity = poolManager.getLiquidity(poolId);
        console.log();
        console.log("after remove liq:", liquidity);

        (, int24 tick,,) = poolManager.getSlot0(poolId);
        console2.log("after remove tick:", tick);
    }

    // ------------ IHook ----------------

    // prevent user fill liquidity
    function beforeModifyPosition(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        if (sender != address(this)) revert SenderMustBeHook();

        return AggregatorHook.beforeModifyPosition.selector;
    }

    // Add liquidity into pool before swap
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        uint256 token0Reserve = 12 ether; //getTokenReserve(token0);
        

        (tickLower, tickUpper, tickMid) = getTicksFromTokenInfo(key);

        console.log();
        console2.log("tickLower", tickLower);
        console2.log("tickUpper", tickUpper);
        console2.log("tickMid", tickMid);
        
        int24 tickSpacing = key.tickSpacing;

        if (tickLower < 0) {
            tickLower = tickLower / tickSpacing * tickSpacing - tickSpacing;
        } else {
            tickLower = tickLower / tickSpacing * tickSpacing;
        }

        if (tickUpper > 0) {
            tickUpper = tickUpper / tickSpacing * tickSpacing + tickSpacing;
        } else {
            tickUpper = tickUpper / tickSpacing * tickSpacing;
        }

        (, int24 tick,uint24 hookswapFee ,) = poolManager.getSlot0(poolId);

        console.log();
        console.log("hookFee:", hookswapFee);
        console.log("round tick by tickSpacing:");
        console2.log("tickLower", tickLower);
        console2.log("tickUpper", tickUpper);
        console2.log("tickMid", tickMid);
        console2.log("slot0 tick:", tick);

        // version 2
        // tickMid = tickLower + key.tickSpacing;

        // if (tickMid == tickUpper) {
        //     tickMid = tickLower + key.tickSpacing / 2;
        // }
        // console2.log("tickMid new", tickMid);

        // version 3
        // tickMid = tickLower + key.tickSpacing;
        // tickUpper = tickLower + 2 * key.tickSpacing;
        // console2.log("tickUpper new", tickUpper);

        // version 4
        // todo fix +/-
        if (tickMid < 0) {
            tickLower = tickMid / tickSpacing * tickSpacing - 2 *tickSpacing;
            tickUpper = tickMid / tickSpacing * tickSpacing + 2 * tickSpacing;
        } else if (tickMid > 0) {
            tickLower = tickMid / tickSpacing * tickSpacing - 2 *tickSpacing;
            tickUpper = tickMid / tickSpacing * tickSpacing + 2 * tickSpacing;
        } else {
            tickLower = tickMid - 2 * tickSpacing;
            tickUpper = tickMid + 2 * tickSpacing;
        }
        tickMid = (tickLower + tickUpper) / 2;

         // one group param
        tickLower = 46873;
        tickUpper = 46874;
        //uint256 token1Reserve = uint(9213376791555881) * uint(1650) / uint(1000);//1 ether; //getTokenReserve(token1);
        uint token1Reserve = uint(9213376791555881);

        /*
        tickLower = 46853;
        tickUpper = 46854;
        uint256 token1Reserve = uint(9213376791555883);
        */

        console.log();
        console.log("version4 ticks:");
        console2.log("tickLower", tickLower);
        console2.log("tickUpper", tickUpper);
        console2.log("tickMid", tickMid);
        console2.log("sqrtPrice:", TickMath.getSqrtRatioAtTick(-tickLower));

        /*
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(tick),
            TickMath.getSqrtRatioAtTick(-tickLower),
            TickMath.getSqrtRatioAtTick(-tickUpper),
            token0Reserve,
            token1Reserve
        );
        */
        uint128 liquidity = _calJITLiquidity(-tickLower, 1 ether, token1Reserve, true);
        console.log("token reserve:", token0Reserve);
        console.log("before deposit:", liquidity);

        BalanceDelta delta = _modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: -tickUpper,
                tickUpper: -tickLower,
                liquidityDelta: int128(liquidity)
            })
        );

        depositedInPoolManager[token0] = uint128(delta.amount0());
        depositedInPoolManager[token1] = uint128(delta.amount1());

        return AggregatorHook.beforeSwap.selector;
    }

    // Remove all liquidity in pool after swap
    /// @notice since user transfer in after the whole swap in PoolSwapTest.sol, 
    /// actually it could not remove liquidty in afterSwap handle if filling liquidity
    /// accurately. So maybe it's no need to add afterSwap.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4) {
        PoolId poolId = key.toId();
        uint128 liquidity = poolManager.getLiquidity(poolId);

        // todo fix this read balance, use poolManage
        uint256 balance0 = depositedInPoolManager[Currency.unwrap(key.currency0)];
        uint256 balance1 = depositedInPoolManager[Currency.unwrap(key.currency1)];

        (, int24 tick,,) = poolManager.getSlot0(poolId);

        uint24 fee = key.fee.getStaticFee();
        console.log("afterSwap fee:", fee);
        console2.log("delta amount1:", delta.amount1());
        console2.log("delta amount0:", delta.amount0());
        console.log("balance1:", balance1);
        console.log("balance0:", balance0);


        uint256 amount0;
        uint256 amount1;

        if (delta.amount0() > 0 && delta.amount1() < 0) {
            amount0 = balance0 + uint128(delta.amount0())* (1000000 - fee) / 1000000; 
            amount1 = balance1 - uint128(-delta.amount1()) ;
        }

        if (delta.amount0() < 0 && delta.amount1() > 0) {
            amount0 = balance0 - uint128(-delta.amount0());
            amount1 = balance1 + uint128(delta.amount1()) * (1000000 - fee) / 1000000;
        }
        console.log("begin afterSwap");
        

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
                TickMath.getSqrtRatioAtTick(tick+100),
                TickMath.getSqrtRatioAtTick(-tickLower),
                TickMath.getSqrtRatioAtTick(-tickUpper),
                amount0,
                amount1
            );
        console.log("\nUsing below amounts to calculate liquidity to be removed");
        console.log("token0 amount", amount0);
        console.log("token1 amount", amount1);
        console.log("liquidity:", liquidity);
        

        uint128 tickliquidity = poolManager.getLiquidity(poolId,address(this), -tickUpper-1,-tickLower-1);
        console.log("owner:", tickliquidity);
        tickliquidity = poolManager.getLiquidity(poolId);
        console.log("all:", tickliquidity);
        
        /*
        _modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: -tickUpper,
                tickUpper: -tickLower,
                liquidityDelta: -int128(liquidity)
            })
        );
        
        */

        return AggregatorHook.afterSwap.selector;
    }

    // -------------- ILockCallback ----------------

    function lockAcquired(bytes calldata rawData)
        external
        override(ILockCallback, BaseHook)
        poolManagerOnly
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;

        if (data.params.liquidityDelta <= 0) { //must contain 0
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);
            console.log("\ntake deltas");
            console2.log("delta amount0", delta.amount0());
            console2.log("delta amount1", delta.amount1());
            _takeDeltas(data.key, delta);
        } else {
            delta = poolManager.modifyPosition(data.key, data.params, ZERO_BYTES);
            console.log("\nsettle deltas");
            console2.log("delta amount0", delta.amount0());
            console2.log("delta amount1", delta.amount1());
            _settleDeltas(data.key, delta);
        }
        return abi.encode(delta);
    }

    // -------------- Internal Functions --------------

    function _calJITLiquidity(int24 curTick, uint256 fromAmount, uint256 toAmount, bool zeroForOne) internal view returns(uint128 liquidity) {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(curTick);
        if(zeroForOne) {
            uint256 tmp1 = fromAmount * uint256(sqrtPriceX96) / Q96 *uint256(sqrtPriceX96) / Q96- toAmount;
            uint256 tmp2 = fromAmount * uint256(sqrtPriceX96) * toAmount / Q96;
            liquidity = uint128(tmp2 / tmp1);
        } else {

        }
    }

    function _modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(poolManager.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function _settleDeltas(PoolKey memory key, BalanceDelta delta) internal {
        _settleDelta(key.currency0, uint128(delta.amount0()));
        _settleDelta(key.currency1, uint128(delta.amount1()));
    }

    function _settleDelta(Currency currency, uint128 amount) internal {
        if (currency.isNative()) {
            poolManager.settle{value: amount}(currency);
        } else {
            currency.transfer(address(poolManager), amount);
            poolManager.settle(currency);
        }
    }

    function _takeDeltas(PoolKey memory key, BalanceDelta delta) internal {
        uint256 amount0 = uint256(uint128(-delta.amount0()));
        uint256 amount1 = uint256(uint128(-delta.amount1()));
        poolManager.take(key.currency0, address(this), amount0);
        poolManager.take(key.currency1, address(this), amount1);
    }

    // D3MM function
    function getTokenReserve(address token) public view returns (uint256) {
        // real: return state.balances[token];
        // mock: return IERC20(token).balanceOf(address(this));
        return IERC20Minimal(token).balanceOf(address(this));
    }
}
