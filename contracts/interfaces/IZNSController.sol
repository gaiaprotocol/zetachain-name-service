// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IZNS.sol";
import "./IZNSResolver.sol";

interface IZNSController {
    error UnchangedData();
    error InvalidName();
    error TooShortDuration();
    error ExpiredDeadline();
    error UsedKey();
    error Unauthorized();
    error InvalidOracle();

    /**
     * e.g.
     * NameRegistered("thegreathb", namehash("thegreathb"), 0x1234....abcd, tokenAddr, 10000, 123456789)
     */
    event NameRegistered(
        string name,
        bytes32 indexed labelHash,
        address indexed nameOwner,
        address indexed token,
        uint256 price,
        uint256 expiries
    );
    /**
     * e.g.
     * NameRenewed("thegreathb", namehash("thegreathb"), tokenAddr, 10000, 123456789)
     */
    event NameRenewed(string name, bytes32 indexed labelHash, address indexed token, uint256 price, uint256 expiries);
    /**
     * e.g.
     * UpdateDomainManager(namehash("thegreathb.gaia"), 0x1234....abcd)
     */
    event UpdateDomainManager(bytes32 indexed node, address indexed manager);
    event SetResolver(IZNSResolver newResolver);
    event SetOracle(address newOracle);
    event SetTreasury(address newTreasury);

    function BASE_NODE() external view returns (bytes32);

    function ADDR_REVERSE_NODE() external view returns (bytes32);

    function MIN_REGISTRATION_DURATION() external view returns (uint256);

    function zns() external view returns (IZNS);

    function resolver() external view returns (IZNSResolver);

    function oracle() external view returns (address);

    function treasury() external view returns (address);

    /**
     * e.g.
     * node : namehash("thegreathb.gaia")
     */
    function domainManagers(bytes32 node) external view returns (address);

    function usedKeys(uint256 key) external view returns (bool);

    /**
     * e.g.
     * name : "thegreathb"
     */
    function valid(string calldata name) external pure returns (bool);

    /**
     * e.g.
     * name : "thegreathb"
     */
    function available(string calldata name) external view returns (bool);

    /**
     * e.g.
     * label : "thegreathb"
     * return : namehash("thegreathb")
     */
    function getLabelHash(string calldata label) external pure returns (bytes32);

    /**
     * e.g.
     * labelHash : namehash("thegreathb")
     * return : namehash("thegreathb.gaia")
     */
    function getNode(bytes32 labelHash) external pure returns (bytes32);

    /**
     * e.g.
     * addr : 0x1234....abcd
     * return : namehash("1234....abcd.addr.reverse")
     */
    function getReverseNode(address addr) external pure returns (bytes32);

    /**
     * e.g.
     * name : "thegreathb"
     */
    function register(
        string calldata name,
        address nameOwner,
        address domainManager,
        uint256 duration,
        bytes calldata data,
        bytes32 r,
        bytes32 vs
    ) external;

    /**
     * e.g.
     * name : "thegreathb"
     */
    function renew(
        string calldata name,
        uint256 duration,
        bytes calldata data,
        bytes32 r,
        bytes32 vs
    ) external;

    /**
     * e.g.
     * labelHash : namehash("thegreathb")
     */
    function updateDomainManager(bytes32 labelHash, address addr) external;

    /**
     * e.g.
     * labelHash : namehash("thegreathb")
     */
    function setAddr(bytes32 labelHash, address addr) external;

    /**
     * e.g.
     * name : "thegreathb.gaia"
     */
    function setName(string calldata name) external;
}
