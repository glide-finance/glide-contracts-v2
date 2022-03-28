import { ethers } from "hardhat";
import { Contract } from "ethers";

export abstract class BaseContract
{
  contract:Contract;
  address:string;

  constructor(contract?:Contract) {
    this.contract = contract!;
    this.address = contract ? contract.address : '0x0';
  }

  static async deployContract(contractName:string, ...args: any[]): Promise<Contract> {
    const factory = await ethers.getContractFactory(contractName);
    return await factory.deploy(...args);
  }
}
