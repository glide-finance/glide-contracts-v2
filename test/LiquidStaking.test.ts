import { expect } from "chai";
import { ethers } from "hardhat";
import { LiquidStaking } from "./utils/LiquidStaking";
import { StElaToken } from "./utils/StElaToken";

describe("LiquidStaking", function () {
  let stElaToken: StElaToken;
  let liquidStaking:LiquidStaking;
  beforeEach(async () => {
    stElaToken = await StElaToken.create();
    liquidStaking = await LiquidStaking.create(stElaToken.address);
  });

  it("Check if works", async function () {
    console.log(liquidStaking.address);
  });
});
