const reaper = require("../src/ReaperSDK.js");
const addresses = require("../Addresses.json");
const { testAccount } = require("../secrets.json");
const { tokens, testnet, mainnet } = require("../Addresses.json");

async function main() {

  let corval = "0x811f9F60bEc5be20aE23c2C2C96c1c88c88D1023";
  let provider = new ethers.providers.JsonRpcProvider("https://rpc.testnet.fantom.network/");
  let self = new ethers.Wallet(testAccount, provider);

  const tx = self.sendTransaction({
    to: corval,
    value: ethers.utils.parseEther("100.0")
});

  let balance = await provider.getBalance(corval);
  let balance2 = await provider.getBalance("0x8B4441E79151e3fC5264733A3C5da4fF8EAc16c1");
  console.log(balance.toString());
  console.log(balance2.toString());

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
