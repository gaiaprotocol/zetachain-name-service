// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IZNSController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

contract ZNSController is IZNSController, Ownable, Multicall {
    using SafeERC20 for IERC20;

    // namehash("gaia")
    bytes32 public constant BASE_NODE = 0x208d08353bf873e56f266090aab1ec351ccad4cc72055f05a0817031e9018b33;
    // namehash("addr.reverse")
    bytes32 public constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
    uint256 public immutable MIN_REGISTRATION_DURATION; // 28 days;

    IZNS public immutable zns;
    IZNSResolver public resolver;
    address public oracle;
    address public treasury;
    mapping(bytes32 => address) public domainManagers;
    mapping(uint256 => bool) public usedKeys;

    constructor(
        IZNS _zns,
        IZNSResolver _resolver,
        address _oracle,
        address _treasury,
        uint256 _minRegDurationDays
    ) {
        zns = _zns;
        _setResolver(_resolver);
        _setOracle(_oracle);
        _setTreasury(_treasury);
        MIN_REGISTRATION_DURATION = 3600 * 24 * _minRegDurationDays;
    }

    // ownership functions
    function setResolver(IZNSResolver _resolver) external onlyOwner {
        _setResolver(_resolver);
    }

    function setOracle(address _oracle) external onlyOwner {
        _setOracle(_oracle);
    }

    function setTreasury(address _treasury) external onlyOwner {
        _setTreasury(_treasury);
    }

    function recoverFunds(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    // internal functions related to ownership
    function _setResolver(IZNSResolver _resolver) internal {
        if (resolver == _resolver) revert UnchangedData();
        resolver = _resolver;
        emit SetResolver(_resolver);
    }

    function _setOracle(address _oracle) internal {
        if (oracle == _oracle) revert UnchangedData();
        oracle = _oracle;
        emit SetOracle(_oracle);
    }

    function _setTreasury(address _treasury) internal {
        if (treasury == _treasury) revert UnchangedData();
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    // external view/pure functions
    function valid(string calldata name) public pure returns (bool) {
        return _strlen(name) >= 3;
    }

    function available(string calldata name) external view returns (bool) {
        return valid(name) && zns.available(uint256(getLabelHash(name)));
    }

    // only label. without ".gaia"
    function getLabelHash(string calldata label) public pure returns (bytes32) {
        return keccak256(bytes(label));
    }

    function getNode(bytes32 labelHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(BASE_NODE, labelHash));
    }

    function getReverseNode(address addr) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, _sha3HexAddress(addr)));
    }

    // external functions
    function register(
        string calldata name,
        address nameOwner,
        address domainManager,
        uint256 duration,
        bytes calldata data,
        bytes32 r,
        bytes32 vs
    ) external {
        if (!valid(name)) revert InvalidName();
        if (duration < MIN_REGISTRATION_DURATION) revert TooShortDuration();

        bytes32 labelHash = getLabelHash(name);
        uint256 price;
        address token;
        {
            // to avoid stack-too-deep error
            uint256 key;
            uint256 deadline;
            (token, price, key, deadline) = abi.decode(data, (address, uint256, uint256, uint256));
            _checkOracle(
                keccak256(
                    abi.encodePacked(labelHash, nameOwner, duration, token, price, key, deadline, block.chainid, address(this))
                ),
                r,
                vs
            );
            if (deadline < block.timestamp) revert ExpiredDeadline();
            if (usedKeys[key]) revert UsedKey();
            usedKeys[key] = true;
        }
        IERC20(token).safeTransferFrom(msg.sender, treasury, price);
        _updateDomainManager(getNode(labelHash), domainManager);

        _register(name, labelHash, nameOwner, token, price, duration);
    }

    function renew(
        string calldata name,
        uint256 duration,
        bytes calldata data,
        bytes32 r,
        bytes32 vs
    ) external {
        if (duration == 0) revert TooShortDuration();
        bytes32 labelHash = getLabelHash(name);
        (address token, uint256 price, uint256 key, uint256 deadline) = abi.decode(
            data,
            (address, uint256, uint256, uint256)
        );
        _checkOracle(
            keccak256(abi.encodePacked(labelHash, duration, token, price, key, deadline, block.chainid, address(this))),
            r,
            vs
        );

        if (deadline < block.timestamp) revert ExpiredDeadline();
        if (usedKeys[key]) revert UsedKey();
        usedKeys[key] = true;

        IERC20(token).safeTransferFrom(msg.sender, treasury, price);

        uint256 expiries = zns.renew(uint256(labelHash), duration);
        emit NameRenewed(name, labelHash, token, price, expiries);
    }

    function updateDomainManager(bytes32 labelHash, address addr) external {
        bytes32 node = getNode(labelHash);
        if (domainManagers[node] != msg.sender && zns.ownerOf(uint256(labelHash)) != msg.sender) revert Unauthorized();
        _updateDomainManager(node, addr);
    }

    function setAddr(bytes32 labelHash, address addr) external {
        bytes32 node = getNode(labelHash);
        if (domainManagers[node] != msg.sender) revert Unauthorized();
        _setAddr(node, addr);
    }

    function setName(string calldata name) external {
        _setName(msg.sender, name);
    }

    // internal functions
    function _checkOracle(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal view {
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        if (ECDSA.recover(message, r, vs) != oracle) revert InvalidOracle();
    }

    function _register(
        string calldata name,
        bytes32 labelHash,
        address nameOwner,
        address token,
        uint256 price,
        uint256 duration
    ) internal {
        uint256 expiries = zns.register(uint256(labelHash), nameOwner, duration);
        emit NameRegistered(name, labelHash, nameOwner, token, price, expiries);
    }

    function _updateDomainManager(bytes32 node, address addr) internal {
        domainManagers[node] = addr;
        emit UpdateDomainManager(node, addr);
    }

    function _setAddr(bytes32 node, address addr) internal {
        resolver.setAddr(node, addr);
    }

    function _setName(address addr, string calldata name) internal {
        resolver.setName(getReverseNode(addr), name);
    }

    function _sha3HexAddress(address addr) internal pure returns (bytes32 ret) {
        assembly {
            let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000

            for {
                let i := 40
            } gt(i, 0) {

            } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }

    function _strlen(string calldata s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;
        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }
}
