/** @type import('hardhat/config').HardhatUserConfig */
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-network-helpers";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-truffle5"
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3"
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy"
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-abi-exporter";
import * as dotenv from "dotenv";

dotenv.config();

const privateKey = process.env.PRIVATE_KEY;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.15",
    settings: {
      optimizer: {
        enabled: true,
        runs: 2
      }
    }
  },
  networks: {
    develop: {
      url: "http://127.0.0.1:9650/ext/bc/C/rpc",
      accounts: [privateKey]
    },
    flare: {
      url: 'https://flare-api.flare.network/ext/C/rpc',
      accounts: [privateKey],
    },
    coston2: {
      url: "https://coston2-api.flare.network/ext/C/rpc",
      accounts: [privateKey],
    },
  },
};

export default config;
