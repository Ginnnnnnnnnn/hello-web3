require("@nomicfoundation/hardhat-toolbox")
require("@nomiclabs/hardhat-ethers")
require('hardhat-contract-sizer')
require('@openzeppelin/hardhat-upgrades')
require('solidity-coverage')

// config
const { config: dotenvConfig } = require("dotenv")
const { resolve } = require("path")
dotenvConfig({ path: resolve(__dirname, "./.env") })

const SEPOLIA_ALCHEMY_AK = process.env.SEPOLIA_ALCHEMY_AK
const SEPOLIA_PK_ONE = process.env.SEPOLIA_PK_ONE
const SEPOLIA_PK_TWO = process.env.SEPOLIA_PK_TWO

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 50,
      },
      viaIR: true,
    },
    metadata: {
      bytecodeHash: 'none',
    }
  },
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${SEPOLIA_ALCHEMY_AK}`,
      accounts: [`${SEPOLIA_PK_ONE}`, `${SEPOLIA_PK_TWO}`],
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
}
