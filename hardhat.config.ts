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
      gas: 1200000000,
      blockGasLimit: 1200000000,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 200000,
      gas: 12000000,
      blockGasLimit: 12000000,
    },
    testnet: {
      chainId: 4201,
      url: process.env.TESTNET_RPC || '',
      accounts: [process.env.TESTNET_DEPLOY_PRIVATE_KEY || ''],
    },
    mainnet: {
      chainId: 42,
      url: process.env.MAINNET_RPC || '',
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
  etherscan: {
    apiKey: {
      testnet: 'no-api-key-needed',
      mainnet: 'no-api-key-needed',
    },
    customChains: [
      {
        network: "testnet",
        chainId: 4201,
        urls: {
          apiURL: "https://api.explorer.execution.testnet.lukso.network/api",
          browserURL: "https://explorer.execution.testnet.lukso.network",
        },
      },
      {
        network: 'mainnet',
        chainId: 42,
        urls: {
          apiURL: 'https://api.explorer.execution.mainnet.lukso.network/api',
          browserURL: 'https://explorer.execution.mainnet.lukso.network',
        },
      },
    ],
  },
};

export default config;
