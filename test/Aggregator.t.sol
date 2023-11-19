// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {AggregatorHook} from "../contracts/hooks/examples/Aggregator.sol";
import {D3Maker} from "../contracts/hooks/examples/D3Maker.sol";
import {AggregatorHookImplementation} from "./shared/implementation/AggregatorImplementation.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {UniswapV4ERC20} from "../contracts/libraries/UniswapV4ERC20.sol";
import {FullMath} from "@uniswap/v4-core/contracts/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {SafeCast} from "@uniswap/v4-core/contracts/libraries/SafeCast.sol";

contract TestAggregatorHook is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using CurrencyLibrary for Currency;

    event Initialize(
        PoolId indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    event ModifyPosition(
        PoolId indexed poolId, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    int24 constant TICK_SPACING = 1; 
    uint16 constant LOCKED_LIQUIDITY = 1000;
    uint256 constant MAX_DEADLINE = 12329839823;
    uint256 constant MAX_TICK_LIQUIDITY = 11505069308564788430434325881101412;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint8 constant DUST = 30;

    uint160 public constant SQRT_RATIO_2_1 = 112045541949572279837463876454;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;

    Currency currency0;
    Currency currency1;

    PoolManager manager;

    AggregatorHookImplementation aggregatorHook = AggregatorHookImplementation(
        address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG))
    );

    PoolKey key;
    PoolId id;

    PoolKey key2;
    PoolId id2;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;

    function stickOneSlot(
        uint256 numberA,
        uint256 numberADecimal,
        uint256 numberB,
        uint256 numberBDecimal
    ) public pure returns (uint256 numberSet) {
        numberSet = (numberA << 32) + (numberADecimal << 24) + (numberB << 8) + numberBDecimal;
    }

    function stickAmount(
        uint256 askAmount,
        uint256 askAmountDecimal,
        uint256 bidAmount,
        uint256 bidAmountDecimal
    ) public pure returns (uint64 amountSet) {
        amountSet = uint64(stickOneSlot(askAmount, askAmountDecimal, bidAmount, bidAmountDecimal));
    }

    function stickPrice(
        uint256 midPrice,
        uint256 midPriceDecimal,
        uint256 feeRate,
        uint256 askUpRate,
        uint256 bidDownRate
    ) public pure returns(uint80 priceInfo) {
        priceInfo = uint80(
            (midPrice << 56) + (midPriceDecimal << 48) + (feeRate << 32) + (askUpRate << 16) + bidDownRate
        );
    }

    function constructToken0Info() public pure returns(D3Maker.TokenMMInfo memory tokenInfo) {
        tokenInfo.priceInfo = stickPrice(1300, 18, 6, 12, 10);
        tokenInfo.amountInfo = stickAmount(100, 18, 100, 18);
    }

    function constructToken1Info() public pure returns(D3Maker.TokenMMInfo memory tokenInfo) {
        tokenInfo.priceInfo = stickPrice(12, 18, 6, 23, 15);
        tokenInfo.amountInfo = stickAmount(100, 18, 100, 18);
    }

    function setUp() public {
        token0 = new MockERC20("TestA", "A", 18, 2 ** 128);
        token1 = new MockERC20("TestB", "B", 18, 2 ** 128);
        token2 = new MockERC20("TestC", "C", 18, 2 ** 128);

        manager = new PoolManager(500000);

        AggregatorHookImplementation impl = new AggregatorHookImplementation(manager, aggregatorHook);
        vm.etch(address(aggregatorHook), address(impl).code);

        key = createPoolKey(token0, token1);
        id = key.toId();

        key2 = createPoolKey(token1, token2);
        id2 = key.toId();

        modifyPositionRouter = new PoolModifyPositionTest(manager);
        swapRouter = new PoolSwapTest(manager);

        token0.approve(address(aggregatorHook), type(uint256).max);
        token1.approve(address(aggregatorHook), type(uint256).max);
        token2.approve(address(aggregatorHook), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
    }


    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB) internal view returns (PoolKey memory) {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 0 , TICK_SPACING, aggregatorHook); // todo if change fee?
    }

    function testHook_BeforeModifyPositionFailsWithWrongMsgSender() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectRevert(AggregatorHook.SenderMustBeHook.selector);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: MIN_TICK, tickUpper: MAX_TICK, liquidityDelta: 100}), ZERO_BYTES
        );
    }

    function testHook_SwapFirstTime() public {
        PoolKey memory testKey = key;
        token0.mint(address(aggregatorHook), 1 ether);
        token1.mint(address(aggregatorHook), 1 ether);
        // price 1200

        bytes memory initData = abi.encode(address(token0), address(token1));
        manager.initialize(testKey, TickMath.getSqrtRatioAtTick(-46855+ 100), initData); // todo: 初始化价格如何确定

        token0.mint(address(aggregatorHook), 1000 ether);
        token1.mint(address(aggregatorHook), 1000 ether);

        // question state hook change is keep, however global variable, even setting constant is zero
        // but if call a write function, it will work
        aggregatorHook.setNewPrice(9213376791555881);
        (uint256 toAmount,,) = aggregatorHook.getMockAmountOut(1 ether, true);
        console.log(toAmount);

        /*
        D3Maker.TokenMMInfo memory token0Info = constructToken0Info();
        D3Maker.TokenMMInfo memory token1Info = constructToken1Info();
        aggregatorHook.setTokenMMInfo(address(token0), token0Info);
        aggregatorHook.setTokenMMInfo(address(token1), token1Info);
        */

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 1 ether, sqrtPriceLimitX96: MIN_SQRT_RATIO + 1});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        snapStart("HookFirstSwap");
        swapRouter.swap(testKey, params, settings, ZERO_BYTES);
        snapEnd();

        /*
        console.log();
        console.log("token0(pool token1) balance in manager", token0.balanceOf(address(manager)));
        console.log("token1(pool token0) balance in manager", token1.balanceOf(address(manager)));
        console.log("token0 balance in aggregatorHook", token0.balanceOf(address(aggregatorHook)));
        console.log("token1 balance in aggregatorHook", token1.balanceOf(address(aggregatorHook)));

        aggregatorHook.removeRemainingLiquidity(key);
        console.log();
        console.log("token0 balance(pool token1) in manager", token0.balanceOf(address(manager)));
        console.log("token1 balance(pool token0) in manager", token1.balanceOf(address(manager)));
        console.log("token0 balance in aggregatorHook", token0.balanceOf(address(aggregatorHook)));
        console.log("token1 balance in aggregatorHook", token1.balanceOf(address(aggregatorHook)));
        */
    }

    function testHook_SwapSecondTime() public {
        testHook_SwapFirstTime();
        PoolKey memory testKey = key;

        // sell token0 to token1, the second time
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 1 ether, sqrtPriceLimitX96: MIN_SQRT_RATIO + 1});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        // notice could not use the same price, not single token deposit cause amount lack 
        // making price diff is too big.
        aggregatorHook.setNewPrice(9212376791555881);

        snapStart("HookSecondSwap");
        swapRouter.swap(testKey, params, settings, ZERO_BYTES);
        snapEnd();
    }
}
