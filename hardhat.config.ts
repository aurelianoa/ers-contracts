import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";

import 'solidity-coverage';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomicfoundation/hardhat-chai-matchers';
import 'solidity-docgen';
import "hardhat-gas-reporter";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      gas: 12000000,
      blockGasLimit: 12000000,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 200000,
      gas: 12000000,
      blockGasLimit: 12000000,
    },
    testnet: {
      chainId: 4201,
      url: process.env.TESTNET_RPC_URL || '',
      accounts: [process.env.TESTNET_DEPLOY_PRIVATE_KEY || ''],
    },
    mainnet: {
      chainId: 42,
      url: process.env.MAINNET_RPC_URL || '',
      accounts: [process.env.MAINNET_DEPLOY_PRIVATE_KEY || ''],
    },
  },
  docgen: {
    exclude: ["mocks", "interfaces", "lib", "token/IPBT.sol"],
    pages: 'files',
  },
  gasReporter: {
    enabled: true,
  },
};

export default config;
