// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {FeeLibrary} from "@uniswap/v4-core/contracts/libraries/FeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/contracts/libraries/FullMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {BaseHook} from "../../BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {ILockCallback} from "@uniswap/v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import "forge-std/Test.sol";

contract D3Maker {
    struct TokenMMInfo {
        // [mid price(16) | mid price decimal(8) | fee rate(16) | ask up rate (16) | bid down rate(16)]
        // midprice unit is 1e18
        // all rate unit is 10000
        uint80 priceInfo;
        // [ask amounts(16) | ask amounts decimal(8) | bid amounts(16) | bid amounts decimal(8) ]
        uint64 amountInfo;
    }

    mapping(address => TokenMMInfo) public tokenInfoMap;

    uint256 public globalMtFee;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint16 internal constant ONE_AMOUNT_BIT = 24;

    // ================= set tokenMMInfo =======================

    // [ask amounts(16) | ask amounts decimal(8) | bid amounts(16) | bid amounts decimal(8) ]
    function parseAskAmount(uint64 amountInfo) public pure returns (uint256 amountWithDecimal) {
        uint256 askAmount = (amountInfo >> (ONE_AMOUNT_BIT + 8)) & 0xffff;
        uint256 askAmountDecimal = (amountInfo >> ONE_AMOUNT_BIT) & 255;
        amountWithDecimal = askAmount * (10 ** askAmountDecimal);
    }

    // [ask amounts(16) | ask amounts decimal(8) | bid amounts(16) | bid amounts decimal(8) ]
    function parseBidAmount(uint64 amountInfo) public pure returns (uint256 amountWithDecimal) {
        uint256 bidAmount = (amountInfo >> 8) & 0xffff;
        uint256 bidAmountDecimal = amountInfo & 255;
        amountWithDecimal = bidAmount * (10 ** bidAmountDecimal);
    }

    function parseAllPrice(uint80 priceInfo, uint256 mtFeeRate)
        public
        pure
        returns (
            uint256 askUpPrice,
            uint256 askDownPrice,
            uint256 bidUpPrice,
            uint256 bidDownPrice,
            uint256 swapFee,
            uint256 midPriceWithDecimal
        )
    {
        {
            uint256 midPrice = (priceInfo >> 56) & 0xffff;
            uint256 midPriceDecimal = (priceInfo >> 48) & 255;
            midPriceWithDecimal = midPrice * (10 ** midPriceDecimal);
            uint256 swapFeeRate = (priceInfo >> 32) & 0xffff;
            uint256 askUpRate = (priceInfo >> 16) & 0xffff;
            uint256 bidDownRate = priceInfo & 0xffff;
            // swap fee rate standarlize
            swapFee = swapFeeRate * (10 ** 14) + mtFeeRate;
            uint256 swapFeeSpread = midPriceWithDecimal * swapFee / 1e18;
            // ask price standarlize
            askDownPrice = midPriceWithDecimal + swapFeeSpread;
            askUpPrice = midPriceWithDecimal + midPriceWithDecimal * askUpRate / (10 ** 4);
            require(askDownPrice <= askUpPrice, "ask price invalid");
            // bid price standarlize
            uint256 reversalBidUp = midPriceWithDecimal - swapFeeSpread;
            uint256 reversalBidDown = midPriceWithDecimal - midPriceWithDecimal * bidDownRate / (10 ** 4);
            require(reversalBidDown <= reversalBidUp, "bid price invalid");
            //bidDownPrice = DecimalMath.reciprocalCeil(reversalBidUp);
            //bidUpPrice = DecimalMath.reciprocalCeil(reversalBidDown);
            bidDownPrice = reversalBidDown;
            bidUpPrice = reversalBidUp;
        }
    }

    function setTokenMMInfo(address token, TokenMMInfo memory info) public {
        tokenInfoMap[token] = info;
    }

    function setGlobalMtFee(uint256 newMtFee) public {
        globalMtFee = newMtFee;
    }

    // todo  support any token pairs. This only for A-usd token. token 0 is A,
    // todo process decimal
    function getTicksFromTokenInfo(PoolKey calldata key)
        public
        view
        returns (int24 tickLower, int24 tickUpper, int24 tickMid)
    {
        (,,uint256 bidUpPriceA, uint256 bidDownPriceA,, uint256 midPriceA) = parseAllPrice(tokenInfoMap[Currency.unwrap(key.currency1)].priceInfo, globalMtFee);
        console.log("TokenA price");
        console.log("bidDownPrice", bidDownPriceA);
        console.log("bidUpPrice", bidUpPriceA);
        console.log("midPrice", midPriceA);
        console.log();

        (uint256 askUpPriceB, uint256 askDownPriceB,,,, uint256 midPriceB) = parseAllPrice(tokenInfoMap[Currency.unwrap(key.currency0)].priceInfo, globalMtFee);
        console.log("TokenB price");
        console.log("askDownPrice", askDownPriceB);
        console.log("askUpPrice", askUpPriceB);
        console.log("midPrice", midPriceB);
        console.log();

        // priceMin = bidDownA / askUpB
        // priceMax = askUpA / bidDownB
        uint256 downPrice = bidDownPriceA * 1e18 / askUpPriceB;
        uint256 upPrice = bidUpPriceA * 1e18 / askDownPriceB;
        uint256 midPrice = midPriceA * 1e18 / midPriceB;
        // uint256 midPrice = 9213376791555881;
        console.log("downPrice", downPrice);
        console.log("upPrice", upPrice);
        console.log("midPrice", midPrice);

        uint160 upPriceSqrtQ = uint160(FullMath.mulDiv(Math.sqrt(upPrice), Q96, 10 ** 9));
        uint160 downPriceSqrtQ = uint160(FullMath.mulDiv(Math.sqrt(downPrice), Q96, 10 ** 9));
        uint160 midPriceSqrtQ = uint160(FullMath.mulDiv(Math.sqrt(midPrice), Q96, 10 ** 9));

        tickLower = TickMath.getTickAtSqrtRatio(downPriceSqrtQ);
        tickUpper = TickMath.getTickAtSqrtRatio(upPriceSqrtQ);
        tickMid = TickMath.getTickAtSqrtRatio(midPriceSqrtQ);
    }
}
