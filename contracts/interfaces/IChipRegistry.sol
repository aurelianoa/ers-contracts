//SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { IProjectRegistrar } from "./IProjectRegistrar.sol";

interface IChipRegistry {

    struct ManufacturerValidation {
        bytes32 enrollmentId;
        bytes manufacturerCertificate;
    }

    function addProjectEnrollment(
        IProjectRegistrar _projectRegistrar,
        address _projectPublicKey,
        bytes32 _nameHash,
        bytes32 _serviceId,
        uint256 _lockinPeriod,
        bytes calldata _signature
    )
        external;

    function addChip(
        address _chipId,
        address _owner,
        bytes32 _nodeLabel,
        ManufacturerValidation calldata _manufacturerValidation
    )
        external;

    function setChipNodeOwner(
        address _chipId,
        address _newOwner
    )
        external;

    function getChipNode(
        address _chipId
    )
        external view returns (bytes32);

    function ownerOf(
        address _chipId
    )
        external view returns (address);

}
