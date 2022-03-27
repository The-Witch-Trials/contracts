async function main() {
  const Auction = await ethers.getContractFactory("Auction")

  // Start deployment, returning a promise that resolves to a contract object
  const auctionDeployable = await Auction.deploy()
  await auctionDeployable.deployed()
  console.log("Contract deployed to address:", auctionDeployable.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })