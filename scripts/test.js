// const MasterChef = artifacts.require("MasterChef");
// const Timelock = artifacts.require("Timelock");
// const ePuddingChef = artifacts.require("ePuddingChef");
const PuddingToken = artifacts.require("PuddingToken");

const admin = "0xE931c0585ef0508955bBC5728411D0f20D6E03bA";

function numToHex(num) {
  return `0x${num.toString(16)}`;
}

module.exports = async function(config) {
  try {
    const pudding = await PuddingToken.new();
    console.log("2");
    await pudding.mint(admin, numToHex(0.2e18));
    console.log("3");
    const balance = await pudding.balanceOf(admin);
    console.log("balance", balance.toString());
  } catch (error) {
    console.log('error', error);
  }
};

