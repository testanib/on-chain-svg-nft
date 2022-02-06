const fs = require('fs');
const { ethers } = require('hardhat');
let {networkConfig} = require('../helper-hardhat-config');
module.exports = async({
    getNamedAccounts,
    deployments,
    getChainId,
}) => {
    const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();
    const chainId = await getChainId();

    log("========================================");
    const SVGNFT = await deploy("SVGNFT", {
        from: deployer,
        log: true,
    });
    log(`SVGNFT: ${SVGNFT.address}`);
    let svg = fs.readFileSync("./img/triangle.svg", "utf8");

    const svgNFTContract = await ethers.getContractFactory("SVGNFT");
    const accounts = await hre.ethers.getSigners();
    const signer = accounts[0];
    const svgNFT = new ethers.Contract(SVGNFT.address, svgNFTContract.interface, signer);
    const networkName = networkConfig[chainId]['name'];
    log(`Verify with:\n npx hardhat verify --network ${networkName} ${svgNFT.address}`)

    //create transaction
    let tx = await svgNFT.create(svg);
    log(`Transaction hash: ${tx.hash}`);
    let receipt = await tx.wait(1);
    log(`TokenURI: ${await svgNFT.tokenURI(0)}`);

}