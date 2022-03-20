import { Contract } from "ethers";
import { ContractBase } from "./BaseContract";

export class LiquidStaking extends ContractBase {
  constructor(contract:Contract) {
    super(contract);
  }

  static async create(_stElaTokenAddress:string): Promise<LiquidStaking> {
    return new LiquidStaking(await ContractBase.deployContract("LiquidStaking", _stElaTokenAddress));
  }
}
