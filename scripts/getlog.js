// pud/usdt 0x737b74c59f79000b6ace7fa97558a4f7bb1ab8d61454ea550306d0b5a9325a3d
// pud/hoo 0x5b804777e00d74aa549dffb15add4cb9cd1f68504e926592c7d153efb6215ea1

module.exports = async function(callback) {
  try {
    const receipt = await web3.eth.getTransactionReceipt('0x5b804777e00d74aa549dffb15add4cb9cd1f68504e926592c7d153efb6215ea1');
    console.log('receipt logs', receipt.logs);
    console.log('receipt rawlogsg', receipt.rawLogs);
  } catch (error) {
    return callback(error);
  }

  callback();
};
