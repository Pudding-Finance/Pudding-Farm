const { assert } = require("chai");

const PuddingToken = artifacts.require('PuddingToken');

contract('PuddingToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.pudding = await PuddingToken.new({ from: minter });
    });


    it('mint', async () => {
        await this.pudding.mint(alice, 1000, { from: minter });
        assert.equal((await this.pudding.balanceOf(alice)).toString(), '1000');
    })
});
