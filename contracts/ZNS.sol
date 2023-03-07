// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IZNS.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ZNS is IZNS, ERC721, Ownable {
    uint256 public immutable GRACE_PERIOD; // 90 days

    mapping(uint256 => uint256) public expiries;
    address public controller;

    constructor(uint256 _gracePeriodDays) ERC721("GaiaNameService", "ZNS") {
        GRACE_PERIOD = 3600 * 24 * _gracePeriodDays;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert InvalidCaller();
        _;
    }

    function setController(address _controller) external onlyOwner {
        _setController(_controller);
    }

    function _setController(address _controller) internal {
        if (controller == _controller) revert UnchangedData();
        controller = _controller;
        emit SetController(_controller);
    }

    function expired(uint256 tokenId) public view returns (bool) {
        return expiries[tokenId] < block.timestamp;
    }

    function ownerOf(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        if (expired(tokenId)) revert InvalidId();
        return super.ownerOf(tokenId);
    }

    function available(uint256 id) public view returns (bool) {
        return expiries[id] + GRACE_PERIOD < block.timestamp;
    }

    /**
     * @dev Register a name.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function register(
        uint256 id,
        address owner,
        uint256 duration
    ) external onlyController returns (uint256) {
        if (!available(id)) revert UnexpiredId();

        expiries[id] = block.timestamp + duration;
        if (_exists(id)) {
            // Name was previously owned, and expired
            _burn(id);
        }
        _mint(owner, id);
        return block.timestamp + duration;
    }

    function renew(uint256 id, uint256 duration) external onlyController returns (uint256) {
        if (available(id)) revert ExpiredId();
        expiries[id] += duration;
        return expiries[id];
    }
}
