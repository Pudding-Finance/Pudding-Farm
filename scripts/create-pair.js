const ORC20 = artifacts.require("ORC20");
const contract = require("@truffle/contract");
const PuddingFactoryData = require("../vendors/PuddingFactory.json");

const PuddingFactory = contract(PuddingFactoryData);
PuddingFactory.setProvider(web3.currentProvider);

const factoryAddress = "0x6168D508ad65D87f8F5916986B55d134Af7153bb";

async function getTokenName(tokenAddress) {
  const orc20 = await ORC20.at(tokenAddress);
  const name = await orc20.symbol.call();

  if (name === "wHOO") {
    return "HOO";
  }

  return name;
}

module.exports = async function(callback) {
  // setteing default from is required, can't figure out why
  const accounts = await web3.eth.getAccounts();
  PuddingFactory.defaults({
    from: accounts[0]
  });

  let factory;
  async function createPair([tokenA, addressA], [tokenB, addressB]) {
    const tokens = await Promise.all([
      getTokenName(addressA),
      getTokenName(addressB)
    ]);
    if (tokens[0].toLowerCase() !== tokenA.toLowerCase()) {
      console.log(
        `Provide symbol "${tokenA}" not match with the address "${addressA}"`
      );
      return;
    }

    if (tokens[1].toLowerCase() !== tokenB.toLowerCase()) {
      console.log(
        `Provide symbol "${tokenB}" not match with the address "${addressB}"`
      );
      return;
    }

    console.log(`create pair ${tokenA}/${tokenB}`);
    const res = await factory.createPair(addressA, addressB);
    console.log(`pair ${tokenA}/${tokenB} created`);
    console.log(`result:`, res.logs);
  }

  try {
    factory = await PuddingFactory.at(factoryAddress);

    // await addLP("tpt/hoo", "xx", 5);
    // await createPair(
    //   ["pud", "0xbE8D16084841875a1f398E6C3eC00bBfcbFa571b"],
    //   ["usdt", "0xD16bAbe52980554520F6Da505dF4d1b124c815a7"]
    // );
    // await createPair(
    //   ["pud", "0xbE8D16084841875a1f398E6C3eC00bBfcbFa571b"],
    //   ["hoo", "0x3EFF9D389D13D6352bfB498BCF616EF9b1BEaC87"]
    // );
    await createPair(
      ["tpt", "0x263e10bE808bafaD9bd62a0998a36d4e6B9fcb19"],
      ["hoo", "0x3EFF9D389D13D6352bfB498BCF616EF9b1BEaC87"]
    );
  } catch (error) {
    return callback(error);
  }

  callback();
};
