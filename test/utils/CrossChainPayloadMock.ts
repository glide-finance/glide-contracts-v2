import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";
import { BaseContract } from "./BaseContract";

export class CrossChainPayloadMock extends BaseContract {
  constructor(contract:Contract) {
    super(contract);
  }

  static async create(): Promise<CrossChainPayloadMock> {
    return new CrossChainPayloadMock(await BaseContract.deployContract("CrossChainPayloadMock"));
  }

  async getContractBalance(): Promise<BigNumber> {
    return ethers.provider.getBalance(this.address);
  }
}
