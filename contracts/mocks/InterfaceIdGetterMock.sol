//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ILSP8IdentifiableDigitalAsset } from "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";

import { IChipRegistry } from "../interfaces/IChipRegistry.sol";
import { IPBT } from "../token/IPBT.sol";
import { IProjectRegistrar } from "../interfaces/IProjectRegistrar.sol";

contract InterfaceIdGetterMock {
    constructor() {}

    function getERC165InterfaceId() external pure returns (bytes4) {
        return type(IERC165).interfaceId;
    }

    function getPBTInterfaceId() external pure returns (bytes4) {
        return type(IPBT).interfaceId;
    }

    function getProjectRegistrarInterfaceId() external pure returns (bytes4) {
        return type(IProjectRegistrar).interfaceId;
    }

    function getChipRegistryInterfaceId() external pure returns (bytes4) {
        return type(IChipRegistry).interfaceId;
    }

    function getLSP8InterfaceId() external pure returns (bytes4) {
        return type(ILSP8IdentifiableDigitalAsset).interfaceId;
    }
}
