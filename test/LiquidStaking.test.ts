import { expect } from "chai";
import { BigNumber, Signer, Transaction } from "ethers";
import { ethers } from "hardhat";
import { CrossChainPayloadMock } from "./utils/CrossChainPayloadMock";
import { LiquidStaking } from "./utils/LiquidStaking";
import { StElaToken } from "./utils/StElaToken";
import { toWei } from "./utils/Utils";

describe("LiquidStaking", function () {
  let stElaToken: StElaToken;
  let crossChainPayloadMock: CrossChainPayloadMock;
  let liquidStaking:LiquidStaking;
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

    const addr = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    feeAmount = 0.0001;

    // Create contracts
    stElaToken = await StElaToken.create();
    crossChainPayloadMock = await CrossChainPayloadMock.create();
    liquidStaking = await LiquidStaking.create(stElaToken, crossChainPayloadMock, addr, feeAmount);
  
    await stElaToken.transferOwnership(owner, liquidStaking.address);

    const amountToDeposit = 1;
    await liquidStaking.depoist(user1, amountToDeposit);

    initialCrossChainPayloadBalance = await crossChainPayloadMock.getContractBalance();
    initialUser1StElaTokenBalance = await stElaToken.balanceOf(await user1.getAddress());
  });

  async function updateEpoch(
    _user:Signer,
    _exchangeRate:number
  ): Promise<void> {
    await liquidStaking.updateEpochFirstStep(_user, _exchangeRate);
    const updateEpochAmount = await liquidStaking.getUpdateEpochAmount();
    await _user.sendTransaction({ from: await _user.getAddress(), to: liquidStaking.address, value: updateEpochAmount });
    await liquidStaking.updateEpochSecondStep(_user);
  }

  it("Check if [setReceivePayloadAddress] works good", async function () {
    const addr = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE";
    await liquidStaking.setReceivePayloadAddress(owner, addr);
    const getAddr = await liquidStaking.getReceivePayloadAddress();

    expect(addr).equal(getAddr);
  });

  it("Check if [setReceivePayloadFee] works good", async function () {
    const feeAmount = 0.001;
    await liquidStaking.setReceivePayloadFee(owner, feeAmount);
    const getFeeAmount = await liquidStaking.getReceivePayloadFee();

    expect(toWei(feeAmount)).equal(getFeeAmount);
  });

  it("Check if [deposit] works good", async function () {
    const amountToDeposit = 1;
    await liquidStaking.depoist(user1, amountToDeposit);

    expect(toWei(amountToDeposit).toString()).equal(((await crossChainPayloadMock.getContractBalance()).sub(initialCrossChainPayloadBalance)));

    const currentStElaTokenBalance = await stElaToken.balanceOf(await user1.getAddress());
    expect(toWei(amountToDeposit - feeAmount).toString()).equal(currentStElaTokenBalance.sub(initialUser1StElaTokenBalance));
  });

  it("Check if [deposit] works good after update epoch", async function () {
    const exchangeRate = 10100;
    await updateEpoch(owner, exchangeRate);

    const amountToDeposit = 1;
    await liquidStaking.depoist(user1, amountToDeposit);

    expect(+toWei(amountToDeposit)).equal(+((await crossChainPayloadMock.getContractBalance()).sub(initialCrossChainPayloadBalance)));
    
    const currentStElaTokenBalance = +(await stElaToken.balanceOf(await user1.getAddress())).sub(initialUser1StElaTokenBalance);

    expect(+toWei((amountToDeposit - feeAmount) * liquidStaking.getExchangeRateDivider() / exchangeRate)).to.be.equal(+currentStElaTokenBalance*1);
  });

  it("Check if [requestWithdraw] works good", async function () {
    const amountToRequestWithdraw = 0.1;
    await liquidStaking.requestWithdraw(user1, amountToRequestWithdraw);

    const currentUser1StElaTokenBalance = await stElaToken.balanceOf(await user1.getAddress());
    expect(toWei(amountToRequestWithdraw)).equal(initialUser1StElaTokenBalance.sub(currentUser1StElaTokenBalance));
  });

  it("Check if [withdraw] works good", async function () {
    const amountToRequestWithdraw = 0.1;
    await liquidStaking.requestWithdraw(user1,amountToRequestWithdraw);

    await updateEpoch(owner, 10000);

    const user1AmountBeforeWithdraw = await user1.getBalance();
    await liquidStaking.withdraw(user1, amountToRequestWithdraw);

    const user1AmountAfterWithdraw = await user1.getBalance();
    expect(+user1AmountAfterWithdraw).lessThanOrEqual(+user1AmountBeforeWithdraw.add(toWei(amountToRequestWithdraw)));
  });

  it("Check if [requestWithdraw] and [withdraw] with hold step works good", async function () {
    const amountToRequestWithdrawBeforeUpdateEpoch = 0.1;
    await liquidStaking.requestWithdraw(user1,amountToRequestWithdrawBeforeUpdateEpoch);

    await liquidStaking.updateEpochFirstStep(owner, 10000);

    const amountToRequestWithdrawAfterUpdateEpoch = 0.15;
    await liquidStaking.requestWithdraw(user1,amountToRequestWithdrawAfterUpdateEpoch);

    const withdrawForExecutesFirstCheck = await liquidStaking.getWithdrawForExecutes(await user1.getAddress());
    expect(withdrawForExecutesFirstCheck.elaOnHoldAmount).equal(toWei(amountToRequestWithdrawBeforeUpdateEpoch));

    const updateEpochAmount = await liquidStaking.getUpdateEpochAmount();
    await owner.sendTransaction({ from: await owner.getAddress(), to: liquidStaking.address, value: updateEpochAmount });
    await liquidStaking.updateEpochSecondStep(owner);

    const user1AmountBeforeWithdraw = await user1.getBalance();
    const stElaTotalSupplyBeforeWithdraw = await stElaToken.totalSupply();
    await liquidStaking.withdraw(user1, amountToRequestWithdrawBeforeUpdateEpoch);

    const withdrawForExecutesSecondCheck = await liquidStaking.getWithdrawForExecutes(await user1.getAddress());
    expect(withdrawForExecutesSecondCheck.elaOnHoldAmount).equal(0);

    const user1AmountAfterWithdraw = await user1.getBalance();
    expect(+user1AmountAfterWithdraw).lessThanOrEqual(+user1AmountBeforeWithdraw.add(toWei(amountToRequestWithdrawBeforeUpdateEpoch)));
  });

  it("Check if [setStElaTransferOwner] works good", async function () {
    const user2Address = await user2.getAddress();
    await liquidStaking.setStElaTransferOwner(owner, await user2.getAddress());
    
    const stElaTransferOwner = await liquidStaking.getStElaTransferOwner();
    expect(stElaTransferOwner).equal(user2Address);
  });

  it("Check if [transferStElaOwnership] works good", async function () {
    const user2Address = await user2.getAddress();
    await liquidStaking.transferStElaOwnership(owner, await user2.getAddress());
    
    const stElaOwner= await stElaToken.owner();
    expect(stElaOwner).equal(user2Address);
  });
});
