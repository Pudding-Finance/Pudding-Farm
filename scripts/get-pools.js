const MasterChef = artifacts.require("MasterChef");


// const admin = "0xE931c0585ef0508955bBC5728411D0f20D6E03bA";
const chefAddress = "0x26eE42a4DE70CEBCde40795853ebA4E492a9547F";

function numToHex(num) {
  return `0x${num.toString(16)}`;
}

module.exports = async function(callback) {
  try {
    const chef = await MasterChef.at(chefAddress);
    const poolLength = await chef.poolLength.call();
    console.log("poolLength", poolLength.toString());
  } catch (error) {
    return callback(error)
  }

  callback()
};
