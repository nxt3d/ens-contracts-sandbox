const { ethers } = require('hardhat')
const { use, expect } = require('chai')
const { solidity } = require('ethereum-waffle')
const { labelhash, namehash, encodeName, FUSES } = require('../test-utils/ens')
const { evm } = require('../test-utils')
const { shouldBehaveLikeERC1155 } = require('./ERC1155.behaviour')
const { shouldSupportInterfaces } = require('./SupportsInterface.behaviour')
const { shouldRespectConstraints } = require('./Constraints.behaviour')
const { ZERO_ADDRESS } = require('@openzeppelin/test-helpers/src/constants')
const { deploy } = require('../test-utils/contracts')
const { EMPTY_BYTES32, EMPTY_ADDRESS } = require('../test-utils/constants')

const abiCoder = new ethers.utils.AbiCoder()

use(solidity)

const ROOT_NODE = EMPTY_BYTES32

const DUMMY_ADDRESS = '0x0000000000000000000000000000000000000001'
const DAY = 86400
const GRACE_PERIOD = 90 * DAY

function increaseTime(delay) {
  return ethers.provider.send('evm_increaseTime', [delay])
}

function mine() {
  return ethers.provider.send('evm_mine')
}

const {
  CANNOT_UNWRAP,
  CANNOT_BURN_FUSES,
  CANNOT_TRANSFER,
  CANNOT_SET_RESOLVER,
  CANNOT_SET_TTL,
  CANNOT_CREATE_SUBDOMAIN,
  PARENT_CANNOT_CONTROL,
  CAN_DO_EVERYTHING,
  IS_DOT_ETH,
  CAN_EXTEND_EXPIRY,
  CANNOT_APPROVE,
} = FUSES

describe('Name Wrapper Proxy', () => {
  let ENSRegistry
  let ENSRegistry2
  let ENSRegistryH
  let BaseRegistrar
  let BaseRegistrar2
  let BaseRegistrarH
  let NameWrapper
  let NameWrapper2
  let NameWrapperH
  let NameWrapperUpgraded
  let MetaDataservice
  let signers
  let accounts
  let account
  let account2
  let hacker
  let result
  let MAX_EXPIRY = 2n ** 64n - 1n

  /* Utility funcs */

  async function registerSetupAndWrapName(
    label,
    account,
    fuses,
    duration = 1 * DAY,
  ) {
    const tokenId = labelhash(label)

    await BaseRegistrar.register(tokenId, account, duration)

    await BaseRegistrar.setApprovalForAll(NameWrapper.address, true)

    await NameWrapper.wrapETH2LD(label, account, fuses, EMPTY_ADDRESS)
  }

  before(async () => {
    signers = await ethers.getSigners()
    account = await signers[0].getAddress()
    account2 = await signers[1].getAddress()
    account3 = await signers[2].getAddress()
    hacker = account3

    EnsRegistry = await deploy('ENSRegistry')
    EnsRegistry2 = EnsRegistry.connect(signers[1])
    EnsRegistryH = EnsRegistry.connect(signers[2])

    BaseRegistrar = await deploy(
      'BaseRegistrarImplementation',
      EnsRegistry.address,
      namehash('eth'),
    )

    BaseRegistrar2 = BaseRegistrar.connect(signers[1])
    BaseRegistrarH = BaseRegistrar.connect(signers[2])

    await BaseRegistrar.addController(account)
    await BaseRegistrar.addController(account2)

    MetaDataservice = await deploy(
      'StaticMetadataService',
      'https://ens.domains',
    )

    //setup reverse registrar

    const ReverseRegistrar = await deploy(
      'ReverseRegistrar',
      EnsRegistry.address,
    )

    await EnsRegistry.setSubnodeOwner(ROOT_NODE, labelhash('reverse'), account)
    await EnsRegistry.setSubnodeOwner(
      namehash('reverse'),
      labelhash('addr'),
      ReverseRegistrar.address,
    )

    const Resolver = await deploy(
      'PublicResolver',
      EnsRegistry.address,
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      ReverseRegistrar.address,
    )
    await ReverseRegistrar.setDefaultResolver(Resolver.address)

    NameWrapper = await deploy(
      'NameWrapper',
      EnsRegistry.address,
      BaseRegistrar.address,
      MetaDataservice.address,
    )
    NameWrapper2 = NameWrapper.connect(signers[1])
    NameWrapperH = NameWrapper.connect(signers[2])
    NameWrapper3 = NameWrapperH

    NameWrapperUpgraded = await deploy(
      'UpgradedNameWrapperMock',
      EnsRegistry.address,
      BaseRegistrar.address,
    )

    //setup the Name Wrapper Proxy contract
    NameWrapperProxy = await deploy(
      'NameWrapperProxy',
      EnsRegistry.address,
      BaseRegistrar.address,
      NameWrapper.address,
    )

    //set the upgradeContract of the NameWrapperProxy contract
    NameWrapperProxy.setUpgradeContract(NameWrapperUpgraded.address)

    // setup .eth
    await EnsRegistry.setSubnodeOwner(
      ROOT_NODE,
      labelhash('eth'),
      BaseRegistrar.address,
    )

    // setup .xyz
    await EnsRegistry.setSubnodeOwner(ROOT_NODE, labelhash('xyz'), account)

    //make sure base registrar is owner of eth TLD
    expect(await EnsRegistry.owner(namehash('eth'))).to.equal(
      BaseRegistrar.address,
    )
  })

  beforeEach(async () => {
    result = await ethers.provider.send('evm_snapshot')
  })
  afterEach(async () => {
    await ethers.provider.send('evm_revert', [result])
  })

  shouldBehaveLikeERC1155(
    () => [NameWrapper, signers],
    [
      namehash('test1.eth'),
      namehash('test2.eth'),
      namehash('doesnotexist.eth'),
    ],
    async (firstAddress, secondAddress) => {
      await BaseRegistrar.setApprovalForAll(NameWrapper.address, true)

      await BaseRegistrar.register(labelhash('test1'), account, 1 * DAY)
      await NameWrapper.wrapETH2LD(
        'test1',
        firstAddress,
        CAN_DO_EVERYTHING,
        EMPTY_ADDRESS,
      )

      await BaseRegistrar.register(labelhash('test2'), account, 86400)
      await NameWrapper.wrapETH2LD(
        'test2',
        secondAddress,
        CAN_DO_EVERYTHING,
        EMPTY_ADDRESS,
      )
    },
  )

  shouldSupportInterfaces(
    () => NameWrapper,
    ['INameWrapper', 'IERC721Receiver'],
  )

  shouldRespectConstraints(
    () => ({
      BaseRegistrar,
      EnsRegistry,
      EnsRegistry2,
      NameWrapper,
      NameWrapper2,
    }),
    () => signers,
  )

  describe.only('upgrade()', () => {
    describe('.eth', () => {
      const encodedName = encodeName('wrapped2.eth')
      const label = 'wrapped2'
      const labelHash = labelhash(label)
      const nameHash = namehash(label + '.eth')

      it('Upgrades a .eth name if sender is owner', async () => {
        await BaseRegistrar.register(labelHash, account, 1 * DAY)
        const expectedExpiry = await BaseRegistrar.nameExpires(labelHash)
        await BaseRegistrar.setApprovalForAll(NameWrapper.address, true)

        expect(await NameWrapper.ownerOf(nameHash)).to.equal(EMPTY_ADDRESS)

        await NameWrapper.wrapETH2LD(
          label,
          account,
          CAN_DO_EVERYTHING,
          EMPTY_ADDRESS,
        )

        // make sure the name has been wrapped.
        expect(await EnsRegistry.owner(nameHash)).to.equal(NameWrapper.address)
        expect(await NameWrapper.ownerOf(nameHash)).to.equal(account)
        expect(await BaseRegistrar.ownerOf(labelHash)).to.equal(
          NameWrapper.address,
        )

        //set the upgradeContract of the NameWrapper contract
        await NameWrapper.setUpgradeContract(NameWrapperProxy.address)

        // set the ownership of the NameWrapper to the proxy contract
        await NameWrapper.transferOwnership(NameWrapperProxy.address)

        const tx = await NameWrapper.upgrade(encodedName, 0)

        // check the upgraded namewrapper is called with all parameters required

        await expect(tx)
          .to.emit(NameWrapperUpgraded, 'NameUpgraded')
          .withArgs(
            encodedName,
            account,
            PARENT_CANNOT_CONTROL | IS_DOT_ETH,
            expectedExpiry.add(GRACE_PERIOD),
            EMPTY_ADDRESS,
            '0x00',
          )
      })
    })
  })
})
