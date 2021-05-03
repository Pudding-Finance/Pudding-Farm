const MasterChef = artifacts.require("MasterChef");
const ORC20 = artifacts.require("ORC20");
const contract = require("@truffle/contract");
const PuddingPairData = require("../vendors/PuddingPair.json");

const PuddingPair = contract(PuddingPairData);
PuddingPair.setProvider(MasterChef.currentProvider);

const chefAddress = "0x26eE42a4DE70CEBCde40795853ebA4E492a9547F";

function numToHex(num) {
  return `0x${num.toString(16)}`;
}

async function getTokenName(tokenAddress) {
  const orc20 = await ORC20.at(tokenAddress);
  const name = await orc20.symbol.call();

  if (name === "wHOO") {
    return "HOO";
  }

  return name;
}

module.exports = async function(callback) {
  let chef;
  async function addLP(symbol, address, point) {
    symbol = symbol.toLowerCase();
    // check pair
    const pair = await PuddingPair.at(address);
    const tokenAddressList = await Promise.all([
      pair.token0.call(),
      pair.token1.call()
    ]);
    const tokens = await Promise.all([
      getTokenName(tokenAddressList[0]),
      getTokenName(tokenAddressList[1])
    ]);
    const isValidSymbol =
      tokens.join("/").toLowerCase() === symbol ||
      tokens
        .reverse()
        .join("/")
        .toLowerCase() === symbol;

    if (!isValidSymbol) {
      console.log(
        `Provide symbol "${symbol}" not match with ${tokens.join("/")}`
      );
      return;
    }

    await chef.add(`${point * 100}`, address, true);
    console.log(`${symbol} added`);
  }

  try {
    chef = await MasterChef.at(chefAddress);

    // CAUTION: never change the order
    await addLP("hoo/usdt", "0xc755b69b0277d7c935466b41f266142d4a9d265b", 10); // 1
    await addLP("pipi/hoo", "0x8041ad91327ed0d3f0ee5934217a070d16ef7aa8", 5); // 2
    await addLP("doge/hoo", "0xb11d9f143acea34afefd21690c6c46f75ee7137e", 5); // 3
    await addLP("eth/hoo", "0x0ee76d03ea11873d32533bb4c53be7fd58b51d8d", 5); // 4
    await addLP("btc/hoo", "0x4c58e80f30629dcac806fdedc29da753dede5781", 5); //  5
    await addLP("dot/hoo", "0x7eda832988314568fedf2ab304ae8151720a3240", 3); //  6
    await addLP("fil/hoo", "0xc9feaf19f8e49fe7e95277df129d0f3285fed154", 3); //  7
    await addLP("eos/hoo", "0x74b890faffbc6b5c6f81d086466e04afc3d21846", 2); //  8
    await addLP("bch/hoo", "0x1cccaaff7d6613b04cb5611efaaa8413b5af542f", 2); //  9

    // await addLP("tpt/hoo", "xx", 5);
    // await addLP("pud/usdt", "xx", 35);
    // await addLP("pud/hoo", "xx", 20);
  } catch (error) {
    return callback(error);
  }

  callback();
};
