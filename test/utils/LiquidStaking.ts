import { BigNumber, Contract, Signer, Transaction } from "ethers";
import { ethers } from "hardhat";
import { CrossChainPayloadMock} from "./CrossChainPayloadMock";
import { StElaToken } from "./StElaToken";
import { BaseContract } from "./BaseContract";
import { toWei } from "./Utils";

export interface WithdrawForExecute {
  stELAAmount: number;
  stELAOnHoldAmount: number;
}
export class LiquidStaking extends BaseContract {
  stElaToken:StElaToken;
  crossChainPayloadMock: CrossChainPayloadMock;

  constructor(contract:Contract, stElaToken: StElaToken, crossChainPayloadMock: CrossChainPayloadMock) {
    super(contract);
    this.stElaToken = stElaToken;
    this.crossChainPayloadMock = crossChainPayloadMock;
  }

  static async create(
    _stElaToken:StElaToken,
    _crossChainPayload:CrossChainPayloadMock,
    _receivePayloadAddress:string,
    _receivePayloadFee:number
  ): Promise<LiquidStaking> {
    return new LiquidStaking(await BaseContract.deployContract(
      "LiquidStaking", 
      _stElaToken.address, 
      _crossChainPayload.address,
      _receivePayloadAddress,
      toWei(_receivePayloadFee)
    ), _stElaToken, _crossChainPayload);
  }

  getExchangeRateDivider():number{
    return 10000;
  }

  async getContractBalance(): Promise<BigNumber> {
    return ethers.provider.getBalance(this.address);
  }

  async getWithdrawForExecutes(_userAddress:string): Promise<WithdrawForExecute> {
    return this.contract.withdrawReady(_userAddress);
  }

  async setReceivePayloadAddress(
    _user:Signer,
    _receivePayloadAddress: string
  ): Promise<Transaction> {
    return this.contract.connect(_user).setReceivePayloadAddress(_receivePayloadAddress);
  }

  async getReceivePayloadAddress(
  ): Promise<string> {
    return this.contract.receivePayloadAddress();
  }

  async setReceivePayloadFee(
    _user:Signer,
    _receivePayloadFee: number
  ): Promise<Transaction> {
    return this.contract.connect(_user).setReceivePayloadFee(toWei(_receivePayloadFee));
  }

  async getReceivePayloadFee(
  ): Promise<number> {
    return this.contract.receivePayloadFee();
  }

  async updateEpochFirstStep(
    _user:Signer,
    _exchangeRate:number
  ): Promise<Transaction> {
    return this.contract.connect(_user).updateEpoch(_exchangeRate);
  }

  async updateEpochSecondStep(
    _user:Signer
  ): Promise<Transaction> {
    return this.contract.connect(_user).enableWithdraw();
  }

  async getUpdateEpochAmount(): Promise<BigNumber> {
    return this.contract.getUpdateEpochAmount();
  }
  
  async depoist(
    _user:Signer,
    _stElaReceiver:string,
    _ethValue:number
  ): Promise<Transaction> {
    return this.contract.connect(_user).deposit(_stElaReceiver, { value: toWei(_ethValue)});
  }

  async requestWithdraw(
    _user:Signer,
    _amount:number
  ): Promise<Transaction> {
    await this.stElaToken.approve(_user, this.address, _amount);
    return this.contract.connect(_user).requestWithdraw(toWei(_amount));
  }

  async withdraw(
    _user:Signer,
    _amount:number,
    _receiver:string
  ): Promise<Transaction> {
    return this.contract.connect(_user).withdraw(toWei(_amount), _receiver);
  }

  async setStElaTransferOwner(
    _user:Signer,
    _stElaTransferOwner:string
  ): Promise<Transaction> {
    return this.contract.connect(_user).setstELATransferOwner(_stElaTransferOwner);
  }

  async getStElaTransferOwner(): Promise<string> {
    return this.contract.stELATransferOwner();
  }

  async transferStElaOwnership(
    _user:Signer,
    _newOwner:string
  ): Promise<Transaction> {
    return this.contract.connect(_user).transferstELAOwnership(_newOwner);
  }
}
