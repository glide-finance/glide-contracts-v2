import { ethers } from "hardhat";
import { BigNumber } from "ethers";

export const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

export function parseDecimal(decimal:Number, decimalBase:number): BigNumber {
    const decimalString = decimal.toString();
    if (decimalString == MAX_UINT256) {
      return BigNumber.from(MAX_UINT256);
    }
    return ethers.utils.parseUnits(decimalString, decimalBase);
}

export function toWei(eth:Number): BigNumber {
    return parseDecimal(eth, 18);
}