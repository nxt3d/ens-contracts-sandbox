//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import {INameWrapperUpgrade} from "../INameWrapperUpgrade.sol";
import "../../registry/ENS.sol";
import "../../ethregistrar/IBaseRegistrar.sol";
import {BytesUtils} from "../BytesUtils.sol";

contract UpgradedNameWrapperMock is INameWrapperUpgrade {
    using BytesUtils for bytes;

    bytes32 private constant ETH_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    ENS public immutable ens;
    IBaseRegistrar public immutable registrar;

    constructor(ENS _ens, IBaseRegistrar _registrar) {
        ens = _ens;
        registrar = _registrar;
    }

    event NameUpgraded(
        bytes name,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry,
        address approved,
        bytes extraData
    );

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
