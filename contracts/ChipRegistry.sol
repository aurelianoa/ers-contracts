//SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { ChipPBT } from "./token/ChipPBT.sol";
import { IChipRegistry } from "./interfaces/IChipRegistry.sol";
import { IERS } from "./interfaces/IERS.sol";
import { IManufacturerRegistry } from "./interfaces/IManufacturerRegistry.sol";
import { IPBT } from "./token/IPBT.sol";
import { IProjectRegistrar } from "./interfaces/IProjectRegistrar.sol";
import { IServicesRegistry } from "./interfaces/IServicesRegistry.sol";
import { ITransferPolicy } from "./interfaces/ITransferPolicy.sol";
import { IDeveloperRegistry } from "./interfaces/IDeveloperRegistry.sol";
import { StringArrayUtils } from "./lib/StringArrayUtils.sol";

import "hardhat/console.sol";

/**
 * @title ChipRegistry
 * @author Arx
 *
 * @notice Entrypoint for resolving chips added to Arx Protocol. Developers can enroll new projects into this registry by specifying a
 * ProjectRegistrar to manage chip claims. Chip claims are forwarded from ProjectRegistrars at which point a ERC-721
 * compliant "token" of the chip is minted to the claimant and other metadata associated with the chip is set. Any project
 * looking to integrate ERS chips should get resolution information about chips from this address. Because chips are
 * represented as tokens any physical chip transfers should also be completed on-chain in order to get full functionality
 * for the chip.
 */
contract ChipRegistry is IChipRegistry, ChipPBT, Ownable {

    using SignatureChecker for address;
    using ECDSA for bytes;
    using StringArrayUtils for string[];

    /* ============ Events ============ */

    event ProjectEnrollmentAdded(                   // Emitted during addProjectEnrollment
        address indexed developerRegistrar,
        address indexed projectRegistrar,
        address indexed transferPolicy,
        address projectPublicKey
    );

    event ChipAdded(                              // Emitted during claimChip
        address indexed chipId,
        address indexed owner,
        bytes32 serviceId,
        bytes32 ersNode,
        bytes32 indexed enrollmentId
    );

    event GatewayURLAdded(string gatewayUrl);               // Emitted during addGatewayURL
    event GatewayURLRemoved(string gatewayUrl);             // Emitted during removeGatewayURL
    event MaxLockinPeriodUpdated(uint256 maxLockinPeriod);  // Emitted during updateMaxLockinPeriod
    event RegistryInitialized(                              // Emitted during initialize
        address ers,
        address servicesRegistry,
        address developerRegistry
    );

    /* ============ Structs ============ */

    // Do we need an identifier to replace the merkle root? nodehash?
    struct ProjectInfo {
        address projectPublicKey;
        bytes32 serviceId;
        ITransferPolicy transferPolicy;
        uint256 lockinPeriod;
        uint256 creationTimestamp;
        bool claimsStarted;
    }
    
    /* ============ Constants ============ */
    bytes32 public constant URI_RECORDTYPE = bytes32("tokenUri");
    bytes32 public constant REDIRECT_URL_RECORDTYPE = bytes32("redirectUrl");
    
    /* ============ State Variables ============ */
    IManufacturerRegistry public immutable manufacturerRegistry;
    IERS public ers;
    IServicesRegistry public servicesRegistry;
    IDeveloperRegistry public developerRegistry;
    bool public initialized;

    mapping(IProjectRegistrar => ProjectInfo) public projectEnrollments;  // Maps ProjectRegistrar addresses to ProjectInfo
    mapping(address => bytes32) public chipNode;                      // Maps chipId to node in ERS
    uint256 public maxLockinPeriod;                                     // Max amount of time chips can be locked into a service after a
                                                                        // project's creation timestamp

    /* ============ Constructor ============ */

    /**
     * @notice Constructor for ChipRegistry
     *
     * @param _manufacturerRegistry     Address of the ManufacturerRegistry contract
     * @param _maxBlockWindow           The maximum amount of blocks a signature used for updating chip table is valid for
     * @param _maxLockinPeriod          The maximum amount of time a chip can be locked into a service for beyond the project's creation timestamp
     * @param _baseURI             The base URI for the tokenURI of chipPBT
    */
    constructor(
        IManufacturerRegistry _manufacturerRegistry,
        uint256 _maxBlockWindow,
        uint256 _maxLockinPeriod,
        string memory _baseURI
    )
        ChipPBT("ERS", "PBT", _maxBlockWindow, _baseURI)
        Ownable()
    {
        manufacturerRegistry = _manufacturerRegistry;
        maxLockinPeriod = _maxLockinPeriod;
    }

    /* ============ External Functions ============ */

    /**
     * @dev ONLY Developer REGISTRAR: Enroll new project in ChipRegistry. This function is only callable by DeveloperRegistrars. In order to use
     * this function the project must first sign a message of the _projectRegistrar address with the _projectPublicKey's matching
     * private key. This key MUST be the same key used to sign all the chip certificates for the project. This creates a link between
     * chip certificates (which may be posted online) and the deployer of the registrar hence making sure that no malicious Developer is able
     * to steal another Developer's chips for their own enrollment (unless the private key happens to be leaked). This function will
     * revert if the project is already enrolled. See documentation for more instructions on how to create a project merkle root.
     *
     * @param _projectRegistrar          Address of the ProjectRegistrar contract
     * @param _projectPublicKey          Public key of the project (used to sign chip certificates and create _signature)
     * @param _transferPolicy            Address of the transfer policy contract governing chip transfers
     * @param _projectOwnershipProof     Signature of the _projectRegistrar address signed by the _projectPublicKey. Proves ownership over the
     *                                   key that signed the chip custodyProofs and developerInclusionProofs   
     */

    function addProjectEnrollment(
        IProjectRegistrar _projectRegistrar,
        address _projectPublicKey,
        bytes32 serviceId,
        ITransferPolicy _transferPolicy,
        uint256 lockinPeriod,
        bytes calldata _projectOwnershipProof
    )
        external
    {
        require(developerRegistry.isDeveloperRegistrar(msg.sender), "Must be Developer Registrar");
        // TODO: evaluate if this is already covered by the ers node check
        require(projectEnrollments[_projectRegistrar].projectPublicKey == address(0), "Project already enrolled");
        // When enrolling a project, public key cannot be zero address so we can use as check to make sure calling address is associated
        // with a project enrollment during claim
        require(_projectPublicKey != address(0), "Invalid project public key");

        // TODO: Cameron wondering if we need this; we could probably skip of projectPublicKey == projectRegistrar.owner...
        // .toEthSignedMessageHash() prepends the message with "\x19Ethereum Signed Message:\n" + message.length and hashes message
        bytes32 messageHash = abi.encodePacked(block.chainid, _projectRegistrar).toEthSignedMessageHash();
        require(_projectPublicKey.isValidSignatureNow(messageHash, _projectOwnershipProof), "Invalid signature");
        

        projectEnrollments[_projectRegistrar] = ProjectInfo({
            projectPublicKey: _projectPublicKey,
            serviceId: serviceId,
            transferPolicy: _transferPolicy,
            lockinPeriod: lockinPeriod,
            creationTimestamp: block.timestamp,
            claimsStarted: false
        });

        emit ProjectEnrollmentAdded(
            msg.sender,
            address(_projectRegistrar),
            _projectPublicKey,
            address(_transferPolicy)
        );
    }

    /**
     * @notice Allow a user to claim a chip from a project enrollment. Enrollment allows the chip to resolve to the project's preferred
     * service. Additionally, claiming creates a Physically-Bound Token representation of the chip.
     *
     * @dev This function will revert if the chip has already been claimed, if invalid certificate data is provided or if the chip is
     * not part of the project enrollment (not in the project merkle root). Addtionally, there are checks to ensure that the calling
     * ProjectRegistrar has implemented the correct ERS logic. This function is EIP-1271 compatible and can be used to verify chip
     * claims tied to an account contract.
     *
     * @param _chipId                       Chip ID (address)
     * @param _chipOwner                    Struct containing information for validating merkle proof, chip owner, and chip's ERS node
     * @param _manufacturerValidation       Struct containing information for chip's inclusion in manufacturer's merkle tree
     */
    
    // TODO: retain claimChip name?

    function addChip(
        address _chipId,
        address _chipOwner,
        ManufacturerValidation memory _manufacturerValidation
    )
        external virtual
    {
        IProjectRegistrar projectRegistrar = IProjectRegistrar(msg.sender);
        ProjectInfo memory projectInfo = projectEnrollments[projectRegistrar];
        
        // Verify the chip is being added by an enrolled project
        require(projectInfo.projectPublicKey != address(0), "Project not enrolled");

        // Verify that the chip doesn't exist yet based on tokenId in ChipPBT
        require(!_exists(tokenIdFor(_chipId)), "Chip already added");
        require(_chipOwner != address(0), "Invalid chip owner");

        // Validate the manufacturer certificate
        _validateManufacturerCertificate(_chipId, _manufacturerValidation);

        // Get the project's root node which is used in the creation of the subnode
        bytes32 rootNode = projectRegistrar.rootNode();
        
        // Verify the chip's ERS node was created by the ProjectRegistrar; this is the source of truth for the chip's ownership
        bytes32 ersNode = keccak256(abi.encodePacked(rootNode, keccak256(abi.encodePacked(_chipId))));
        require(ers.recordExists(ersNode), "Inconsistent state in ERS");
        chipNode[_chipId] = ersNode;

        // TODO: consider if we want to store a lookup against manufacturer enrollmentIds
        // chipManufacturerEnrollments[_chipId] = _manufacturerValidation.enrollmentId;

        // Lockin Period is min of the lockinPeriod specified by the Developer and the max time period specified by governance
        uint256 lockinPeriod = projectInfo.creationTimestamp + maxLockinPeriod > projectInfo.lockinPeriod ?
            projectInfo.lockinPeriod :
            projectInfo.creationTimestamp + maxLockinPeriod;
        
        // Set primaryService on ServicesRegistry
        servicesRegistry.setInitialService(
            _chipId,
            projectInfo.serviceId,
            lockinPeriod
        );

        // Mint the ChipPBT token
        ChipPBT._mint(_chipOwner, _chipId, projectInfo.transferPolicy);

        if (!projectInfo.claimsStarted) {
            projectEnrollments[projectRegistrar].claimsStarted = true;
        }

        emit ChipAdded(
            _chipId,
            _chipOwner,
            projectInfo.serviceId,
            ersNode,
            _manufacturerValidation.enrollmentId
        );
    }

    /**
     * @notice Included for compliance with EIP-5791 standard but left unimplemented to ensure transfer policies can't be ignored.
     */
    function transferTokenWithChip(
        bytes calldata /*signatureFromChip*/,
        uint256 /*blockNumberUsedInSig*/,
        bool /*useSafeTransfer*/
    )
        public
        virtual
        override(ChipPBT, IPBT)
    {
        revert("Not implemented");
    }

    /**
     * @notice Allow a user to transfer a chip to a new owner, new owner must submit transaction. Use ChipPBT logic which calls
     * TransferPolicy to execute the transfer of the PBT and chip. Update chip's ERS node in order to keep data consistency. EIP-1271
     * compatibility should be implemented in the chip's TransferPolicy contract.
     *
     * @param chipId                Chip ID (address) of chip being transferred
     * @param signatureFromChip     Signature of keccak256(msg.sender, blockhash(blockNumberUsedInSig), _payload) signed by chip
     *                              being transferred
     * @param blockNumberUsedInSig  Block number used in signature
     * @param useSafeTransferFrom   Indicates whether to use safeTransferFrom or transferFrom
     * @param payload               Encoded payload containing data required to execute transfer. Data structure will be dependent
     *                              on implementation of TransferPolicy
     */
    function transferToken(
        address chipId,
        bytes calldata signatureFromChip,
        uint256 blockNumberUsedInSig,
        bool useSafeTransferFrom,
        bytes calldata payload
    ) 
        public
        override(ChipPBT, IPBT)
    {
        // Validations happen in ChipPBT / TransferPolicy
        ChipPBT.transferToken(chipId,  signatureFromChip, blockNumberUsedInSig, useSafeTransferFrom, payload);
        _setERSOwnerForChip(chipId, msg.sender);
    }

    /**
     * @dev ONLY CHIP OWNER (enforced in ChipPBT): Sets the owner for a chip. Chip owner must submit transaction
     * along with a signature from the chipId commiting to a block the signature was generated. This is to prevent
     * any replay attacks. If the transaction isn't submitted within the MAX_BLOCK_WINDOW from the commited block
     * this function will revert. Additionally, the chip's ERS node owner is updated to maintain state consistency.
     *
     * @param _chipId           The chipId to set the owner for
     * @param _newOwner         The address of the new chip owner
     * @param _commitBlock      The block the signature is tied to (used to put a time limit on the signature)
     * @param _signature        The signature generated by the chipId (should just be a signature of the commitBlock)
     */
    function setOwner(
        address _chipId,
        address _newOwner,
        uint256 _commitBlock,
        bytes calldata _signature
    )
        public
        override
    {   
        // Validations happen in ChipPBT, ERC721 doesn't allow transfers to the zero address
        ChipPBT.setOwner(_chipId, _newOwner, _commitBlock, _signature);
        _setERSOwnerForChip(_chipId, _newOwner);
    }

    /* ============ External Admin Functions ============ */

    /**
     * @notice ONLY OWNER: Initialize ChipRegistry contract with ERS and Services Registry addresses. Required due to order of operations
     * during deploy.
     *
     * @param _ers                       Address of the ERS contract
     * @param _servicesRegistry          Address of the ServicesRegistry contract
     * @param _developerRegistry         Address of the DeveloperRegistry contract
     */
    function initialize(IERS _ers, IServicesRegistry _servicesRegistry, IDeveloperRegistry _developerRegistry) external onlyOwner {
        require(!initialized, "Contract already initialized");
        ers = _ers;
        servicesRegistry = _servicesRegistry;
        developerRegistry = _developerRegistry;

        initialized = true;
        emit RegistryInitialized(address(_ers), address(_servicesRegistry), address(_developerRegistry));
    }

    /**
     * @notice ONLY OWNER: Update the maximum amount of time a chip can be locked into a service for beyond the project's creation timestamp
     *
     * @param _maxLockinPeriod         The new maximum amount of time a chip can be locked into a service for beyond the project's creation timestamp
     */
    function updateMaxLockinPeriod(uint256 _maxLockinPeriod) external onlyOwner {
        require(_maxLockinPeriod > 0, "Invalid lockin period");

        maxLockinPeriod = _maxLockinPeriod;
        emit MaxLockinPeriodUpdated(_maxLockinPeriod);
    }

    /* ============ View Functions ============ */

    // TODO: replace resolveUnclaimedChip with a validateUnclaimedChip function; this would validate that a chip is in a specific manufacturer enrollment, e.g.
    // function validateUnclaimedChip(
        // Expects a chipId and enrollmentId
    // )

    /**
     * @notice Return the primary service content.
     *
     * @param _chipId           The chip public key
     * @return                  The content associated with the chip (if chip has been claimed already)
     */
    function resolveChipId(address _chipId) external view returns (IServicesRegistry.Record[] memory) {
        return servicesRegistry.getPrimaryServiceContent(_chipId);
    }

    /**
     * @notice Get tokenUri from tokenId. TokenURI associated with primary service takes precedence, if no tokenURI as
     * part of primary service then fail over to tokenURI defined in ChipPBT.
     *
     * @param _tokenId          Chip's tokenId
     * @return                  TokenUri
     */
    function tokenURI(uint256 _tokenId) public view override(ChipPBT, IERC721Metadata) returns (string memory) {
        string memory tokenUri = _getChipPrimaryServiceContentByRecordType(address(uint160(uint256(_tokenId))), URI_RECORDTYPE);
        return bytes(tokenUri).length == 0 ? ChipPBT.tokenURI(_tokenId) : tokenUri;
    }

    /**
     * @notice Get tokenUri from chip address. TokenURI associated with primary service takes precedence, if no tokenURI as
     * part of primary service then fail over to tokenURI defined in ChipPBT.
     *
     * @param _chipId           Chip's address
     * @return                  TokenUri
     */
    function tokenURI(address _chipId) public view override returns (string memory) {
        string memory tokenUri = _getChipPrimaryServiceContentByRecordType(_chipId, URI_RECORDTYPE);
        return bytes(tokenUri).length == 0 ? ChipPBT.tokenURI(_chipId) : tokenUri;
    }

    /* ============ Internal Functions ============ */

    /**
     * Get ERS node from tokenData and then sets the new Owner of the chip on the ERSRegistry.
     */
    function _setERSOwnerForChip(address _chipId, address _newOwner) internal {
        // TODO: is there a way to get chipErsNode without decoding tokenData?
        // (bytes32 chipErsNode, ) = _decodeTokenData(chipTable[_chipId].tokenData);
        bytes32 chipErsNode = chipNode[_chipId];
        ers.setNodeOwner(chipErsNode, _newOwner);
    }

    function _validateManufacturerCertificate(
        address chipId,
        ManufacturerValidation memory _manufacturerValidation
    )
        internal
        view
    {
        bool isEnrolledChip = manufacturerRegistry.isEnrolledChip(
            _manufacturerValidation.enrollmentId,
            chipId,
            _manufacturerValidation.manufacturerCertificate
        );
        require(isEnrolledChip, "Chip not enrolled with ManufacturerRegistry");
    }

    /**
     * @notice Grab passed record type of primary service. For purposes of use within this contract we convert bytes
     * to string
     *
     * @param _chipId          Chip's address
     * @param _recordType      Bytes32 hash representing the record type being queried
     * @return                 Content cotained in _recordType
     */
    function _getChipPrimaryServiceContentByRecordType(
        address _chipId,
        bytes32 _recordType
    )
        internal
        view
        returns (string memory)
    {
        bytes memory content = servicesRegistry.getPrimaryServiceContentByRecordtype(_chipId, _recordType);
        return string(content);
    }

    /**
     * ChipPBT has an unstructured "tokenData" field that for our implementation we will populate with the chip's
     * ERS node and the manufacturer enrollmentId of the chip. This function structures that data.
     */
    function _encodeTokenData(bytes32 _ersNode, bytes32 _enrollmentId) internal pure returns (bytes memory) {
        // Since no addresses there's no difference between abi.encode and abi.encodePacked
        return abi.encode(_ersNode, _enrollmentId);
    }

    /**
     * ChipPBT has an unstructured "tokenData" field that for our implementation we will populate with the chip's
     * ERS node and the manufacturer enrollmentId of the chip. This function interprets that data.
     */
    function _decodeTokenData(bytes memory _tokenData) internal pure returns (bytes32, bytes32) {
        return abi.decode(_tokenData, (bytes32, bytes32));
    }
}
