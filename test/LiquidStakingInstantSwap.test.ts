import { expect } from "chai";
import { BigNumber, Signer, Transaction } from "ethers";
import { ethers } from "hardhat";
import { LiquidStakingInstantSwap } from "./utils/LiquidStakingInstantSwap";
import { CrossChainPayloadMock } from "./utils/CrossChainPayloadMock";
import { LiquidStaking } from "./utils/LiquidStaking";
import { StElaToken } from "./utils/StElaToken";
import { toWei } from "./utils/Utils";

describe("LiquidStakingInstantSwap", function () {
  let stElaToken: StElaToken;
  let crossChainPayloadMock: CrossChainPayloadMock;
  let liquidStaking:LiquidStaking;
  let liquidStakingInstantSwap:LiquidStakingInstantSwap;
  let owner:Signer
  let user1:Signer;
  let user2:Signer;
  let feeAmount: number;
  let initialCrossChainPayloadBalance:BigNumber;
  let initialUser1StElaTokenBalance: BigNumber;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];

    const addr = "ELASTOS_ADDRESS";

    feeAmount =  0.0001; 

    // Create contracts
    stElaToken = await StElaToken.create();
    crossChainPayloadMock = await CrossChainPayloadMock.create();
    liquidStaking = await LiquidStaking.create(stElaToken, crossChainPayloadMock, addr,feeAmount);
    liquidStakingInstantSwap = await LiquidStakingInstantSwap.create(stElaToken, liquidStaking, 9970);

    await stElaToken.transferOwnership(owner, liquidStaking.address);

    const amountToDeposit = 1;
    await liquidStaking.depoist(user1, amountToDeposit);

    await owner.sendTransaction({ from: await owner.getAddress(), to: liquidStakingInstantSwap.address, value: toWei(5) });

    initialCrossChainPayloadBalance = await crossChainPayloadMock.getContractBalance();
    initialUser1StElaTokenBalance = await stElaToken.balanceOf(await user1.getAddress());
  });

  it("Check if [swap] works good", async function () {
    const amountToSwap = 1 - feeAmount;
    const user2BalanceBeforeSwap = await user2.getBalance();
    await liquidStakingInstantSwap.swap(user1, amountToSwap, await user2.getAddress());
    
    expect(await stElaToken.balanceOf(liquidStakingInstantSwap.address)).equal(toWei(amountToSwap));
    expect(await stElaToken.balanceOf(await user1.getAddress())).equal(0);
    expect(await user2.getBalance()).equal(user2BalanceBeforeSwap.add(toWei(amountToSwap).mul(9970).div(10000)));
  });

  it("Check if [withdrawStEla] works good", async function () {
    const amountToSwap = 1 - feeAmount;
    await liquidStakingInstantSwap.swap(user1, amountToSwap, await user2.getAddress());
    
    await liquidStakingInstantSwap.withdrawStEla(owner, amountToSwap);
    
    expect(await stElaToken.balanceOf(liquidStakingInstantSwap.address)).equal(0);
    expect(await stElaToken.balanceOf(await owner.getAddress())).equal(toWei(amountToSwap));
  });
})