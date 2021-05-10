const { expectRevert, time } = require("@openzeppelin/test-helpers");
const PuddingToken = artifacts.require("PuddingToken");
const ePudHooChef = artifacts.require("ePuddingHooChef");
const PuddingBar = artifacts.require("PuddingBar");
const MockORC20 = artifacts.require("libs/MockORC20");

function getStakingReward(staked, totalStaked, block) {
  const tokenPerBlock = 10;
  const v = (staked / totalStaked) * block * tokenPerBlock;
  return v;
}

async function getBalance(address) {
  return await web3.eth.getBalance(address);
}

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
    await this.chef.recieveReward({ from: alice, value: '100000' });
    // await web3.eth.sendTransaction({ from: deployer, to: this.chef, value: '10000000000'})
  });

  it("deposit", async () => {
    let aliceStartBalance = await getBalance(alice);
    let bobStartBalance = await getBalance(bob);
    let deployerBalance = await getBalance(deployer);
    // let chefBalance = await getBalance(this.chef);

    console.log('alice', alice, aliceStartBalance);
    console.log('bob', bob, bobStartBalance);
    console.log('deployer', deployer, deployerBalance);
   // console.log('chefBalance', this.chef.address, chefBalance);

    await time.advanceBlockTo(currentBlock + 170);

    await this.chef.deposit(100, { from: alice });

    await time.advanceBlockTo(currentBlock + 180);

    console.log('alice', await getBalance(alice));
    console.log('alice pendingReward', (await this.chef.pendingReward(alice)).toString());

    await this.chef.deposit(0, { from: alice });

    console.log('alice', await getBalance(alice));
    // let awardedNum = getStakingReward(20, 20, 1);

    // let aliceBalance = await getBalance(alice);
    // assert.equal(aliceStartBalance + awardedNum, aliceBalance);
  });
});
