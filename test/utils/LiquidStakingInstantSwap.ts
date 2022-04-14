import { Contract, Signer, Transaction } from "ethers";
import { StElaToken } from "./StElaToken";
import { BaseContract } from "./BaseContract";
import { toWei } from "./Utils";
import { LiquidStaking } from "./LiquidStaking";

export class LiquidStakingInstantSwap extends BaseContract {
    stElaToken: StElaToken;
    liquidStaking: LiquidStaking;

    constructor(contract:Contract, _stElaToken: StElaToken, _liquidStaking: LiquidStaking) {
      super(contract);
      this.stElaToken = _stElaToken;
      this.liquidStaking = _liquidStaking;
    }
  
    static async create(
      _stElaToken:StElaToken,
      _liquidStaking:LiquidStaking,
      _feeRange:number
    ): Promise<LiquidStakingInstantSwap> {
      return new LiquidStakingInstantSwap(await BaseContract.deployContract(
        "LiquidStakingInstantSwap", 
        _stElaToken.address, 
        _liquidStaking.address,
        _feeRange
      ), _stElaToken, _liquidStaking);
    }

    async withdrawStEla(
        _user:Signer,
        _stElaAmount:number,
        _receiver:string
    ): Promise<Transaction> {
        return this.contract.connect(_user).withdrawstELA(toWei(_stElaAmount), _receiver);
    }

    async swap(
        _user:Signer,
        _stElaAmount:number,
        _receiver:string
    ): Promise<Transaction> {
        await this.stElaToken.approve(_user, this.address, _stElaAmount);
        return this.contract.connect(_user).swap(toWei(_stElaAmount), _receiver);
    }
}  