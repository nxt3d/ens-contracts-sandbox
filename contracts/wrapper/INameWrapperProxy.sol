//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "../registry/ENS.sol";
import "../ethregistrar/IBaseRegistrar.sol";
import "./IMetadataService.sol";
import "./INameWrapperUpgrade.sol";

interface INameWrapperProxy is IERC165 {
    function setUpgradeContract(INameWrapperUpgrade _upgradeAddress) external;

    function setMetadataService(IMetadataService _metadataService) external;
}
