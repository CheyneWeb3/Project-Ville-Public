// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice ERC-1155 items for consumables/upgrades/outputs.
contract Items1155 is ERC1155, ERC1155Supply, ERC1155Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory uri_, address admin) ERC1155(uri_) {
        require(admin != address(0), "Items1155: admin=0");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function setURI(string calldata newUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newUri);
    }

    function mint(address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        _mintBatch(to, ids, amounts, data);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
