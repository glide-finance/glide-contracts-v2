import { Contract } from "ethers";
import { ContractBase } from "./BaseContract";

export class StElaToken extends ContractBase {
  constructor(contract:Contract) {
    super(contract);
  }

  static async create(): Promise<StElaToken> {
    return new StElaToken(await ContractBase.deployContract("StElaToken"));
  }
}
