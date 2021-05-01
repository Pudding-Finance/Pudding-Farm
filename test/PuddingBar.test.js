const { advanceBlockTo } = require('@openzeppelin/test-helpers/src/time');
const { assert } = require('chai');
const PuddingToken = artifacts.require('PuddingToken');
const PuddingBar = artifacts.require('PuddingBar');

contract('PuddingBar', ([alice, bob, carol, dev, minter]) => {
  beforeEach(async () => {
    this.pudding = await PuddingToken.new({ from: minter });
    this.xPudding = await PuddingBar.new(this.pudding.address, { from: minter });
  });

  it('mint', async () => {
    await this.xPudding.mint(alice, 1000, { from: minter });
    assert.equal((await this.xPudding.balanceOf(alice)).toString(), '1000');
  });

  it('burn', async () => {
    await advanceBlockTo('650');
    await this.xPudding.mint(alice, 1000, { from: minter });
    await this.xPudding.mint(bob, 1000, { from: minter });
    assert.equal((await this.xPudding.totalSupply()).toString(), '2000');
    await this.xPudding.burn(alice, 200, { from: minter });

    assert.equal((await this.xPudding.balanceOf(alice)).toString(), '800');
    assert.equal((await this.xPudding.totalSupply()).toString(), '1800');
  });

  it('safePuddingTransfer', async () => {
    assert.equal(
      (await this.pudding.balanceOf(this.xPudding.address)).toString(),
      '0'
    );
    await this.pudding.mint(this.xPudding.address, 1000, { from: minter });
    await this.xPudding.safePuddingTransfer(bob, 200, { from: minter });
    assert.equal((await this.pudding.balanceOf(bob)).toString(), '200');
    assert.equal(
      (await this.pudding.balanceOf(this.xPudding.address)).toString(),
      '800'
    );
    await this.xPudding.safePuddingTransfer(bob, 2000, { from: minter });
    assert.equal((await this.pudding.balanceOf(bob)).toString(), '1000');
  });
});
