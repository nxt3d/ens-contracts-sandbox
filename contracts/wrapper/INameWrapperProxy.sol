//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "../registry/ENS.sol";
import "../ethregistrar/IBaseRegistrar.sol";
import "./IMetadataService.sol";
import "./INameWrapperUpgrade.sol";

interface INameWrapperProxy {
    function ens() external view returns (ENS);

    function registrar() external view returns (IBaseRegistrar);

    function metadataService() external view returns (IMetadataService);

    function upgradeContract() external view returns (INameWrapperUpgrade);

    function supportsInterface(bytes4 interfaceID) external view returns (bool);

    function setMetadataService(IMetadataService _metadataService) external;

    function wrapFromUpgrade(
        bytes calldata name,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry,
        address approved,
        bytes calldata extraData
    ) external;
}
