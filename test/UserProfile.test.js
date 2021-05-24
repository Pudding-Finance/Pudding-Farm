const { expectRevert } = require("@openzeppelin/test-helpers");
const PuddingToken = artifacts.require("PuddingToken");
const UserProfile = artifacts.require("UserProfile");

contract("UserProfile", ([alice, bob, carol, dev]) => {
  let pudding;
  let userProfile;

  beforeEach(async () => {
    pudding = await PuddingToken.new({ from: dev });
    userProfile = await UserProfile.new(pudding.address, "100", {
      from: dev
    });

    await pudding.mint(alice, "1000", { from: dev });
    await pudding.mint(bob, "1000", { from: dev });
    await pudding.mint(carol, "1000", { from: dev });

    await pudding.approve(userProfile.address, "1000", { from: alice });
    await pudding.approve(userProfile.address, "1000", { from: bob });
    await pudding.approve(userProfile.address, "1000", { from: carol });
  });

  it("set/get avatar", async () => {
    await userProfile.setAvatar("1", { from: alice });
    assert.equal((await pudding.balanceOf(alice)).toString(), "900");

    expectRevert(userProfile.setAvatar("2"), "avatar has already been set");

    assert.equal(await userProfile.getAvatar({ from: alice }), "1");
  });

  it("should return total users", async () => {
    assert.equal(
      (await userProfile.getTotalUsers({ from: dev })).toString(),
      "0"
    );

    await userProfile.setAvatar("1", { from: alice });

    assert.equal(
      (await userProfile.getTotalUsers({ from: dev })).toString(),
      "1"
    );
  });

  it("hasAvatar should work", async () => {
    assert.equal(await userProfile.hasAvatar(alice), false);

    await userProfile.setAvatar("1", { from: alice });

    assert.equal(await userProfile.hasAvatar(alice), true);
  });

  it("protected method should only be called by owner", async () => {
    expectRevert(
      userProfile.getTotalUsers({ from: alice }),
      "caller is not the owner"
    );
  });

  it("withdraw should work", async () => {
    await userProfile.setAvatar("1", { from: alice });
    await userProfile.setAvatar("1", { from: bob });

    expectRevert(
      userProfile.withdraw("100", { from: carol }),
      "caller is not the owner"
    );

    await userProfile.withdraw("200", { from: dev });
    assert.equal((await pudding.balanceOf(dev)).toString(), "200");
  });
});
