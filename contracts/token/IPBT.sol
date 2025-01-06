// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Contract for PBTs (Physical Backed Tokens).
/// NFTs that are backed by a physical asset, through a chip embedded in the physical asset.
interface IPBT {
    /// @dev Returns the ERC-721 `tokenId` for a given chip address.
    ///      Reverts if `chipId` has not been paired to a `tokenId`.
    ///      For minimalism, this will NOT revert if the `tokenId` does not exist.
    ///      If there is a need to check for token existence, external contracts can
    ///      call `LSP8.tokenOwnerOf(bytes32 tokenId)` and check if it passes or reverts.
    /// @param chipId The address for the chip embedded in the physical item
    ///               (computed from the chip's public key).
    function tokenIdFor(address chipId) external view returns (bytes32 tokenId);

    /// @dev Returns true if `signature` is signed by the chip assigned to `tokenId`, else false.
    ///      Reverts if `tokenId` has not been paired to a chip.
    ///      For minimalism, this will NOT revert if the `tokenId` does not exist.
    ///      If there is a need to check for token existence, external contracts can
    ///      call `ELSP8.tokenOwnerOf(bytes32 tokenId)` and check if it passes or reverts.
    /// @param tokenId LSP8 `tokenId`.
    /// @param data      Arbitrary bytes string that is signed by the chip to produce `signature`.
    /// @param signature EIP-191 signature by the chip to check.
    function isChipSignatureForToken(bytes32 tokenId, bytes calldata data, bytes calldata signature)
        external
        view
        returns (bool);

    /// @dev Transfers the token into the address.
    ///      Returns the `tokenId` transferred.
    /// @param to                  The recipient. Dynamic to allow easier transfers to vaults.
    /// @param chipId              Chip ID (address) of chip being transferred.
    /// @param chipSignature       EIP-191 signature by the chip to authorize the transfer.
    /// @param signatureTimestamp  Timestamp used in `chipSignature`.
    ///                            instead of `transferFrom`.
    /// @param extras              Additional data that can be used for additional logic/context
    ///                            when the PBT is transferred.
    /// @dev                        compatible with LSP8 Standard
    /// @param _force               When set to `true`, `to` may be any address. When set to `false`, `to` must be a contract that 
    ///                             supports the LSP1 standard.
    /// @param data                 Additional data the caller wants included in the emitted event, and sent in the hooks 
    ///                             to `from` and `to` addresses.
    function transferToken(
        address to,
        address chipId,
        bytes calldata chipSignature,
        uint256 signatureTimestamp,
        bytes calldata extras,
        bool _force,
        bytes memory data
    ) external returns (bytes32 tokenId);

    /// @dev Emitted when `chipId` is paired to `tokenId`.
    /// `tokenId` may not necessarily exist during assignment.
    /// Indexers can combine this event with the {LSP8.Transfer} event to
    /// infer which tokens exists and are paired with a chip ID.
    event ChipSet(bytes32 indexed tokenId, address indexed chipId);
}