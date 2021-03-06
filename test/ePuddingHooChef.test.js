const { expectRevert, time } = require("@openzeppelin/test-helpers");
const ORC20 = artifacts.require("ORC20");
const PuddingToken = artifacts.require("PuddingToken");
const ePudHooChef = artifacts.require("ePuddingHooChef");
const PuddingBar = artifacts.require("PuddingBar");

function getStakingReward(staked, totalStaked, block) {
  const tokenPerBlock = 10;
  const v = (staked / totalStaked) * block * tokenPerBlock;
  return web3.utils.toBN(v);
}

async function getBalanceOf(tokenAddress, account) {
  const token = await ORC20.at(tokenAddress);

  let balance;
  try {
    balance = await token.balanceOf(account);
  } catch (error) {
    balance = 0;
  }

  return balance;
}

// async function getBalance(address) {
//   const balance = await web3.eth.getBalance(address);
//   return web3.utils.toBN(balance);
// }

contract("ePudHooChef", ([alice, bob, deployer]) => {
  let currentBlock;

  beforeEach(async () => {
    currentBlock = await web3.eth.getBlockNumber();

    this.pudding = await PuddingToken.new({ from: deployer });
    this.xPudding = await PuddingBar.new(this.pudding.address, {
      from: deployer
    });
    this.chef = await ePudHooChef.new(
      this.xPudding.address,
      10,
      currentBlock + 100,
      currentBlock + 200,
      {
        from: deployer
      }
    );

    this.xPudding.approve(this.chef.address, 1000, { from: alice });
    this.xPudding.approve(this.chef.address, 1000, { from: bob });

    await this.xPudding.mint(alice, 100, { from: deployer });
    await this.xPudding.mint(bob, 100, { from: deployer });
    await web3.eth.sendTransaction({
      from: deployer,
      to: this.chef.address,
      value: "100000"
    });
  });

  it("deposit/withdraw", async () => {
    await time.advanceBlockTo(currentBlock + 170);

    let xpudBalance = await getBalanceOf(this.xPudding.address, alice);
    assert.equal(xpudBalance.toString(), "100");

    await this.chef.deposit(100, { from: alice });
    xpudBalance = await getBalanceOf(this.xPudding.address, alice);
    assert.equal(xpudBalance.toString(), "0");

    await this.chef.withdraw(100, { from: alice });
    xpudBalance = await getBalanceOf(this.xPudding.address, alice);
    assert.equal(xpudBalance.toString(), "100");

    expectRevert(
      this.chef.withdraw(1, { from: alice }),
      "revert withdraw: not good"
    );
  });

  it("reward", async () => {
    await time.advanceBlockTo(currentBlock + 170);

    await this.chef.deposit(100, { from: alice });

    await time.advanceBlockTo(currentBlock + 180);

    assert.equal(
      (await this.chef.pendingReward(alice)).toString(),
      getStakingReward(100, 100, 9).toString()
    );

    await this.chef.withdraw(100, { from: alice });
    assert.equal((await this.chef.pendingReward(alice)).toString(), "0");
  });
});
