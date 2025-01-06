// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { 
    LSP8IdentifiableDigitalAsset
} from "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";
import {
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {
    _LSP8_TOKENID_FORMAT_NUMBER
} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

/**
 * @notice An implementation of Lukso's LSP8 that's publicly readonly (no approvals or transfers exposed).
 */
contract LSP8ReadOnly is LSP8IdentifiableDigitalAsset {
    constructor(
        string memory _name,
        string memory _symbol,
        address _newOwner
    ) LSP8IdentifiableDigitalAsset(
        _name,
        _symbol,
        _newOwner,
        _LSP4_TOKEN_TYPE_NFT,
        _LSP8_TOKENID_FORMAT_NUMBER
    ) {}

    function authorizeOperator(address, bytes32, bytes memory) public virtual override {
        revert("LSP8 public approve not allowed");
    }

    function isOperatorFor(
        address,
        bytes32 tokenId
    ) public view virtual override returns (bool) {
        require(_exists(tokenId), "LSP8: invalid token ID");
        return false;
    }

    function getOperatorsOf(
        bytes32 tokenId
    ) public view virtual override returns (address[] memory) {
        require(_exists(tokenId), "LSP8: invalid token ID");
        address[] memory operators = new address[](1);
        return operators;
    }

    function transfer(address, address, bytes32, bool, bytes memory) public virtual override {
        revert("LSP8 public transferFrom not allowed");
    }
}