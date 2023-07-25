//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE, PARENT_CANNOT_CONTROL, CAN_DO_EVERYTHING, IS_DOT_ETH, CAN_EXTEND_EXPIRY, PARENT_CONTROLLED_FUSES, USER_SETTABLE_FUSES} from "./INameWrapper.sol";
import {ERC1155Fuse} from "./ERC1155Fuse.sol";
import {INameWrapperUpgrade} from "./INameWrapperUpgrade.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMetadataService} from "./IMetadataService.sol";

contract NameWrapperProxy is Ownable {
    INameWrapper nameWrapper;
    INameWrapperUpgrade upgradeContract;

    // create a constructor that sets the nameWrapper address
    constructor(INameWrapper _nameWrapper) {
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

    /**
     * @notice Upgrades a domain of any kind. Could be a .eth name vitalik.eth, a DNSSEC name vitalik.xyz, or a subdomain
     * @dev Can be called by the owner or an authorised caller
     * @param name The name to upgrade, in DNS format
     * @param extraData Extra data to pass to the upgrade contract
     */

    function upgrade(bytes calldata name, bytes calldata extraData) public {
        bytes32 node = name.namehash(0);

        if (address(upgradeContract) == address(0)) {
            revert CannotUpgrade();
        }

        if (!canModifyName(node, msg.sender)) {
            revert Unauthorised(node, msg.sender);
        }

        (address currentOwner, uint32 fuses, uint64 expiry) = getData(
            uint256(node)
        );

        address approved = getApproved(uint256(node));

        _burn(uint256(node));

        upgradeContract.wrapFromUpgrade(
            name,
            currentOwner,
            fuses,
            expiry,
            approved,
            extraData
        );
    }
}
