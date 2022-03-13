// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./interfaces/IGlideFactory.sol";
import "./GlidePair.sol";

contract GlideFactory is IGlideFactory {
    using SafeMath for uint256;

    address public override feeTo;
    address public override feeToSetter;

    bytes32 public initCodeHash;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event SetAdminAddress(address indexed caller, address indexed newAddress);
    event SetFeeAddress(address indexed caller, address indexed newAddress);

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
        initCodeHash = keccak256(
            abi.encodePacked(type(GlidePair).creationCode)
        );
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (address pair)
    {
        require(tokenA != tokenB, "Glide: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "Glide: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Glide: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(GlidePair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IGlidePair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "Glide: FORBIDDEN");
        feeTo = _feeTo;
        emit SetFeeAddress(msg.sender, _feeTo);
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "Glide: FORBIDDEN");
        feeToSetter = _feeToSetter;
        emit SetAdminAddress(msg.sender, _feeToSetter);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB)
        public
        pure
        override
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "GlideFactory: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "GlideFactory: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB)
        public
        view
        override
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                bytes20(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(this),
                            keccak256(abi.encodePacked(token0, token1)),
                            initCodeHash
                        )
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB)
        public
        view
        override
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0, ) = sortTokens(tokenA, tokenB);
        pairFor(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IGlidePair(
            pairFor(tokenA, tokenB)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure override returns (uint256 amountB) {
        require(amountA > 0, "GlideFactory: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "GlideFactory: INSUFFICIENT_LIQUIDITY"
        );
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256 amountOut) {
        require(amountIn > 0, "GlideFactory: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "GlideFactory: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn.mul(9975);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256 amountIn) {
        require(amountOut > 0, "GlideFactory: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "GlideFactory: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn.mul(amountOut).mul(10000);
        uint256 denominator = reserveOut.sub(amountOut).mul(9975);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "GlideFactory: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "GlideFactory: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                path[i - 1],
                path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
