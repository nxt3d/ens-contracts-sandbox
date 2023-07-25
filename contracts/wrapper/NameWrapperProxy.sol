//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {INameWrapper, IS_DOT_ETH} from "./INameWrapper.sol";
import {INameWrapperUpgrade} from "./INameWrapperUpgrade.sol";
import {INameWrapperProxy} from "./INameWrapperProxy.sol";
import {ERC1155Fuse} from "./ERC1155Fuse.sol";
import {INameWrapperUpgrade} from "./INameWrapperUpgrade.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMetadataService} from "./IMetadataService.sol";
import {ENS} from "../registry/ENS.sol";
import {IBaseRegistrar} from "../ethregistrar/IBaseRegistrar.sol";
import {BytesUtils} from "./BytesUtils.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract NameWrapperProxy is
    INameWrapperProxy,
    INameWrapperUpgrade,
    Ownable,
    ERC165
{
    INameWrapper public nameWrapper;
    INameWrapperUpgrade public upgradeContract;

    ENS public ens;
    IBaseRegistrar public registrar;

    using BytesUtils for bytes;

    bytes32 private constant ETH_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    constructor(
        ENS _ens,
        IBaseRegistrar _registrar,
        INameWrapper _nameWrapper
    ) {
        ens = _ens;
        registrar = _registrar;
        nameWrapper = _nameWrapper;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(INameWrapperUpgrade).interfaceId ||
            interfaceId == type(INameWrapperProxy).interfaceId ||
            super.supportsInterface(interfaceId);
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

        // If the name is a second level .eth then change the registrant to the upgrade contract.
        if (fuses & IS_DOT_ETH == IS_DOT_ETH) {
            registrar.transferFrom(
                address(nameWrapper),
                address(upgradeContract),
                uint256(labelhash)
            );
        }

        // Change the owner in the registry to the upgrade contract.
        ens.setOwner(node, address(upgradeContract));

        upgradeContract.wrapFromUpgrade(
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
