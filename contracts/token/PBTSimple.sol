//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC165, ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { 
    LSP8IdentifiableDigitalAsset
} from "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { ChipValidations } from "../lib/ChipValidations.sol";
import { LSP8ReadOnly } from "./LSP8ReadOnly.sol";
import { IPBT } from "./IPBT.sol";
import { ITransferPolicy } from "../interfaces/ITransferPolicy.sol";

/**
 * @title PBTSimple
 * @author Arx
 *
 * @notice Implementation of PBT where tokenIds are assigned to chip addresses as the chips are added. The contract has a
 * transfer policy, which can be set by the chip owner and allows the owner to specify how the chip can be transferred to another party. 
 */
contract PBTSimple is IPBT, ERC165, LSP8ReadOnly {
    using SignatureChecker for address;
    using ChipValidations for address;
    using ECDSA for bytes;
    using ECDSA for bytes32;
    using Strings for uint256;

    /* ============ Events ============ */

    event TransferPolicyChanged(address transferPolicy);    // Emitted in setTransferPolicy

    /* ============ Modifiers ============ */

    modifier onlyChipOwner(address _chipId) {
        require(tokenOwnerOf(tokenIdFor(_chipId)) == msg.sender, "Caller must be chip owner");
        _;
    }

    modifier onlyMintedChip(address _chipId) {
        require(_exists(_chipId), "Chip must be minted");
        _;
    }
    
    /* ============ State Variables ============ */
    uint256 public immutable maxBlockWindow;                     // Amount of blocks from commitBlock after which chip signatures are expired
    ITransferPolicy public transferPolicy;                       // Transfer policy for the PBT
    mapping(address=>bytes32) public chipIdToTokenId;            // Maps chipId to tokenId
    mapping(bytes32=>address) public tokenIdToChipId;            // Maps tokenId to chipId
    /* ============ Constructor ============ */

    /**
     * @dev Constructor for ClaimedPBT. Sets the name and symbol for the token.
     *
     * @param _name             The name of the token
     * @param _symbol           The symbol of the token
     * @param _maxBlockWindow   The maximum amount of blocks a signature used for updating chip table is valid for
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _onwer,
        uint256 _maxBlockWindow,
        ITransferPolicy _transferPolicy
    )
        LSP8ReadOnly(_name, _symbol, _onwer)
    {
        maxBlockWindow = _maxBlockWindow;
        transferPolicy = _transferPolicy;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Allow a user to transfer a chip to a new owner with additional checks. A transfer policy must be set in order for
     * transfer to go through. The data contained in _payload will be dependent on the implementation of the transfer policy, however
     * the signature should be signed by the chip. EIP-1271 compatibility should be implemented in the chip's TransferPolicy contract.
     *
     * @param chipId                Chip ID (address) of chip being transferred
     * @param signatureFromChip     Signature of keccak256(msg.sender, blockhash(blockNumberUsedInSig), _payload) signed by chip
     *                              being transferred
     * @param blockNumberUsedInSig  Block number used in signature
     * @param payload               Encoded payload containing data required to execute transfer. Data structure will be dependent
     *                              on implementation of TransferPolicy
     * @dev                         compatible with LSP8 Standard
     * @param _force                When set to `true`, `to` may be any address. When set to `false`, `to` must be a contract that 
     *                              supports the LSP1 standard.
     * @param data                  Additional data the caller wants included in the emitted event, and sent in the hooks 
     *                              to `from` and `to` addresses.
     */
    function transferToken(
        address to,
        address chipId,
        bytes calldata signatureFromChip,
        uint256 blockNumberUsedInSig,
        bytes calldata payload,
        bool _force,
        bytes memory data
    ) 
        public
        virtual
        onlyMintedChip(chipId)
        returns (bytes32 tokenId)
    {
        // ChipInfo memory chipInfo = chipTable[chipId];
        address chipOwner = tokenOwnerOf(tokenIdFor(chipId));

        // Check that the signature is valid, create own scope to prevent stack-too-deep error
        {
            bytes32 signedHash = _createSignedHash(blockNumberUsedInSig, payload);
            require(chipId.isValidSignatureNow(signedHash, signatureFromChip), "Invalid signature");
        }

        _transferPBT(to, chipOwner, tokenIdFor(chipId), _force, data);

        // Validation of the payload beyond ensuring it was signed by the chip is left up to the TransferPolicy contract.
        //authorizeTransfer(address _chipId, address _sender, address _chipOwner, bytes _payload, bytes _signature)
        transferPolicy.authorizeTransfer(
            chipId,
            to,
            msg.sender,
            chipOwner,
            payload,
            signatureFromChip
        );

        return tokenIdFor(chipId);
    }

    /* ============ View Functions ============ */

    /**
     * @dev Using OpenZeppelin's SignatureChecker library, checks if the signature is valid for the payload. Library is
     * ERC-1271 compatible, so it will check if the chipId is a contract and if so, if it implements the isValidSignature.
     *
     * @param _tokenId      The tokenId to check the signature for
     * @param _payload      The payload to check the signature for
     * @param _signature    The signature to check
     * @return bool         If the signature is valid, false otherwise
     */
    function isChipSignatureForToken(bytes32 _tokenId, bytes calldata _payload, bytes calldata _signature)
        public
        view
        returns (bool)
    {
        bytes32 _payloadHash = abi.encodePacked(_payload).toEthSignedMessageHash();
        address _chipId = tokenIdToChipId[_tokenId];
        return _chipId.isValidSignatureNow(_payloadHash, _signature);
    }

    /**
     * @dev Returns the tokenId for a given chipId
     *
     * @param _chipId       The chipId to get the tokenId for
     * @return tokenId      The tokenId for the given chipId
     */
    function tokenIdFor(address _chipId) public view returns (bytes32 tokenId) {
        require(chipIdToTokenId[_chipId] != 0x0, "Chip must be minted");
        return chipIdToTokenId[_chipId];
    }

    /**
     * 
     * @param _interfaceId The interface ID to check for
     */
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(LSP8IdentifiableDigitalAsset, ERC165)
        returns (bool)
    {
        return _interfaceId == 
            type(IPBT).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Sets the transfer policy for PBTSimple.
     * @param _newPolicy    The address of the new transfer policy. We allow the zero address in case owner doesn't want to allow xfers.
     */
    function _setTransferPolicy(
        ITransferPolicy _newPolicy
    )
        internal
        virtual
    {
        require(address(_newPolicy) != address(0), "Transfer policy cannot be zero address");

        // Set the transfer policy
        transferPolicy = _newPolicy;

        emit TransferPolicyChanged(address(_newPolicy));
    }

    /**
     * @dev Mints a new token and assigns it to the given address. Also adds the chipId to the tokenIdToChipId mapping,
     * adds the ChipInfo to the chipTable, and increments the tokenIdCounter.
     *
     * @param _to           The address to mint the token to
     * @param _chipId       The chipId to mint the token for
     * @return uint256      The tokenId of the newly minted token
     */
    function _mint(
        address _to,
        address _chipId,
        bytes32 _ersNode,
        bool _force,
        bytes memory data
    )
        internal
        virtual
        returns(bytes32)
    {
        bytes32 tokenId = _ersNode;
        _mint(_to, tokenId, _force, data);

        chipIdToTokenId[_chipId] = tokenId;
        tokenIdToChipId[tokenId] = _chipId;

        emit ChipSet(tokenId, _chipId);
        return tokenId;
    }

    function _createSignedHash(
        uint256 _blockNumberUsedInSig,
        bytes memory _customPayload
    )
        internal
        virtual
        returns (bytes32)
    {
        // The blockNumberUsedInSig must be in a previous block because the blockhash of the current
        // block does not exist yet.
        require(block.number >= _blockNumberUsedInSig, "Block number must have been mined");
        require(block.number - _blockNumberUsedInSig <= maxBlockWindow, "Block number must be within maxBlockWindow");

        return abi.encodePacked(msg.sender, blockhash(_blockNumberUsedInSig), _customPayload).toEthSignedMessageHash();
    }

    /**
     * @notice Handle transfer of PBT inclusing whether to transfer using safeTransfer. The _to address is always the msg.sender.
     *
     * @param _from                 Address of owner transferring PBT
     * @param _tokenId              ID of PBT being transferred
     * @dev                         compatible with LSP8 Standard
     * @param _force                When set to `true`, `to` may be any address. When set to `false`, `to` must be 
     *                              a contract that supports the LSP1 standard.
     * @param data                  Additional data the caller wants included in the emitted event, and sent in 
     *                              the hooks to `from` and `to` addresses.
     */
    function _transferPBT(
        address to,
        address _from,
        bytes32 _tokenId,
        bool _force,
        bytes memory data
    ) internal {
        _transfer(_from, to, _tokenId, _force, data);
    }

    /**
     * @dev Indicates whether the chipId has been claimed or not
     *
     * @param _chipId       The chipId to check
     * @return bool         True if the chipId has been claimed, false otherwise
     */
    function _exists(address _chipId) internal view returns (bool) {
        // TODO: review this logic closely; ERC721.sol will revert if the tokenId doen't exist
        return chipIdToTokenId[_chipId] != 0x0;
    }
}
