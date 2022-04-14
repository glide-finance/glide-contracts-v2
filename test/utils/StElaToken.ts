import { BigNumber, Contract, Signer, Transaction } from "ethers";
import { BaseContract } from "./BaseContract";
import { toWei } from "./Utils";

export class StElaToken extends BaseContract {
  constructor(contract:Contract) {
    super(contract);
  }

  static async create(): Promise<StElaToken> {
    return new StElaToken(await BaseContract.deployContract("stELAToken"));
  }

  async transferOwnership(_user:Signer, _newOwner: String): Promise<Transaction> {
    return this.contract.connect(_user).transferOwnership(_newOwner);
  }

  async balanceOf(_user: String): Promise<BigNumber> {
    return this.contract.balanceOf(_user);
  }

  async approve(_user:Signer, _spender: String, _amount: number): Promise<Transaction> {
    return this.contract.connect(_user).approve(_spender, toWei(_amount));
  }

  async totalSupply(): Promise<BigNumber> {
    return this.contract.totalSupply();
  }

  async owner(): Promise<string> {
    return this.contract.owner();
  }
}
