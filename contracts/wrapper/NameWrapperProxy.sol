//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {INameWrapper} from "./INameWrapper.sol";
import {ERC1155Fuse} from "./ERC1155Fuse.sol";
import {INameWrapperUpgrade} from "./INameWrapperUpgrade.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMetadataService} from "./IMetadataService.sol";
import {ENS} from "../registry/ENS.sol";
import {IBaseRegistrar} from "../ethregistrar/IBaseRegistrar.sol";
import {BytesUtils} from "./BytesUtils.sol";

contract NameWrapperProxy is Ownable {
    INameWrapper nameWrapper;
    INameWrapperUpgrade upgradeContract;

    ENS ens;
    IBaseRegistrar registrar;

    using BytesUtils for bytes;

    bytes32 private constant ETH_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    event NameUpgraded(
        bytes name,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry,
        address approved,
        bytes extraData
    );

    constructor(
        ENS _ens,
        IBaseRegistrar _registrar,
        INameWrapper _nameWrapper
    ) {
        ens = _ens;
        registrar = _registrar;
        nameWrapper = _nameWrapper;
    }

    /* Metadata service */

    /**
     * @notice Set the metadata service of the NameWrapper. Only the owner can do this
     * @param _metadataService The new metadata service
     */

    function setMetadataService(
        IMetadataService _metadataService
    ) public onlyOwner {
        nameWrapper.setMetadataService(_metadataService);
    }

    /**
     * @notice Set the address of the upgradeContract of the contract. only admin can do this
     * @dev The default value of upgradeContract is the 0 address. Use the 0 address at any time
     * to make the contract not upgradable.
     * @param _upgradeAddress address of an upgraded contract
     */

    function setUpgradeContract(
        INameWrapperUpgrade _upgradeAddress
    ) public onlyOwner {
        upgradeContract = _upgradeAddress;
    }

    function wrapFromUpgrade(
        bytes calldata name,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry,
        address approved,
        bytes calldata extraData
    ) public {
        (bytes32 labelhash, uint256 offset) = name.readLabel(0);
        bytes32 parentNode = name.namehash(offset);
        bytes32 node = _makeNode(parentNode, labelhash);

        // Check to make sure we are the owner of the name.
        if (parentNode == ETH_NODE) {
            address registrant = registrar.ownerOf(uint256(labelhash));
            require(registrant == address(this));
        }

        address owner = ens.owner(node);
        require(owner == address(this));

        // To really check that we are the owner change the resolver to this address and the TTL to 100
        ens.setRecord(node, address(this), address(this), 100);

        emit NameUpgraded(
            name,
            wrappedOwner,
            fuses,
            expiry,
            approved,
            extraData
        );
    }

    function _makeNode(
        bytes32 node,
        bytes32 labelhash
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(node, labelhash));
    }
}
