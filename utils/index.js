const Big = require("big.js");
const web3 = require("web3");

const SECONDS_PER_BLOCK = 3;

function getDeadAddress() {
  return "0x000000000000000000000000000000000000dead";
}

function numToHex(num) {
  return `0x${num.toString(16)}`;
}

function getBlockFromTime(time, knownBlock, knownBlockTime) {
  time = typeof time === "string" ? new Date(time) : time;
  knownBlockTime =
    typeof knownBlockTime === "string"
      ? new Date(knownBlockTime)
      : knownBlockTime;
  const seconds = Math.ceil((time.getTime() - knownBlockTime.getTime()) / 1000);

  return knownBlock + Math.floor(seconds / SECONDS_PER_BLOCK);
}

function formatDecimals(num, precision = 2) {
  const magicNum = Math.pow(10, precision);
  return Math.floor(num * magicNum) / magicNum;
}

function formatUnits(number, units = 2, decimalPlaces) {
  const num = new Big(web3.utils.toBN(number).toString());
  return num.div(new Big(10).pow(units)).toFixed(decimalPlaces, Big.roundDown);
}

module.exports = {
  getDeadAddress,
  numToHex,
  getBlockFromTime,
  formatDecimals,
  formatUnits
};
