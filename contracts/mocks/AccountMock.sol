//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ILSP1UniversalReceiver as ILSP1 } from "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiver.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IPBT } from "../token/IPBT.sol";

contract AccountMock is IERC1271 {

    using ECDSA for bytes32;

    bytes4 public constant MAGIC_VALUE = 0x1626ba7e;

    address public publicKey;
    IPBT public chipRegistry;

    constructor(address _publicKey, address _chipRegistry) {
        publicKey = _publicKey;
        chipRegistry = IPBT(_chipRegistry);
    }

    function transferToken(
        address to,
        address chipId,
        bytes calldata signatureFromChip,
        uint256 blockNumberUsedInSig,
        bytes calldata payload
    )
        external
    {
        chipRegistry.transferToken(to, chipId, signatureFromChip, blockNumberUsedInSig, payload, true, "");
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view override returns (bytes4) {
        if (_hash.recover(_signature) == publicKey) {
            return MAGIC_VALUE;
        } else {
            return 0xffffffff;
        }
    }

    function universalReceiver(
        bytes32 /*typeId*/,
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return ILSP1.universalReceiver.selector;
    }
}
