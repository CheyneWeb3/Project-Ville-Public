/**
 *Submitted for verification at testnet.bscscan.com on 2025-12-22
*/

// File: @openzeppelin/contracts/utils/Errors.sol


// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

// File: @openzeppelin/contracts/utils/Create2.sol


// OpenZeppelin Contracts (last updated v5.1.0) (utils/Create2.sol)

pragma solidity ^0.8.20;


/**
 * @dev Helper to make usage of the `CREATE2` EVM opcode easier and safer.
 * `CREATE2` can be used to compute in advance the address where a smart
 * contract will be deployed, which allows for interesting new mechanisms known
 * as 'counterfactual interactions'.
 *
 * See the https://eips.ethereum.org/EIPS/eip-1014#motivation[EIP] for more
 * information.
 */
library Create2 {
    /**
     * @dev There's no code to deploy.
     */
    error Create2EmptyBytecode();

    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     *
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) internal returns (address addr) {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }
        if (bytecode.length == 0) {
            revert Create2EmptyBytecode();
        }
        assembly ("memory-safe") {
            addr := create2(amount, add(bytecode, 0x20), mload(bytecode), salt)
            // if no address was created, and returndata is not empty, bubble revert
            if and(iszero(addr), not(iszero(returndatasize()))) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }
        if (addr == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}. Any change in the
     * `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return computeAddress(salt, bytecodeHash, address(this));
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) internal pure returns (address addr) {
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := and(keccak256(start, 85), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}

// File: https://github.com/ArielRin/InHaus-Multichain-Staking-System-Public-Files/blob/main/Contracts/IERC6551.sol


pragma solidity ^0.8.19;

interface IERC6551Registry {

    event AccountCreated(
        address account,
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    );

    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 seed
    ) external returns (address);

    function account(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) external view returns (address);
}

interface IERC6551AccountProxy {
    function implementation() external view returns (address);
}

interface IERC6551Account {
    event TransactionExecuted(address indexed target, uint256 indexed value, bytes data);

    receive() external payable;

    function executeCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory);

    function nftInfo()
        external
        view
        returns (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        );

    function owner() external view returns (address);

    function nonce() external view returns (uint256);
}

// File: https://github.com/ArielRin/InHaus-Multichain-Staking-System-Public-Files/blob/main/Contracts/ERC6551Bytecode.sol


pragma solidity ^0.8.19;


library Bytecode {
  error InvalidCodeAtRange(uint256 _size, uint256 _start, uint256 _end);

  /**
    @notice Generate a creation code that results on a contract with `_code` as bytecode
    @param _code The returning value of the resulting `creationCode`
    @return creationCode (constructor) for new contract
  */
  function creationCodeFor(bytes memory _code) internal pure returns (bytes memory) {
    /*
      0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
      0x01    0x80         0x80        DUP1                size size
      0x02    0x60         0x600e      PUSH1 14            14 size size
      0x03    0x60         0x6000      PUSH1 00            0 14 size size
      0x04    0x39         0x39        CODECOPY            size
      0x05    0x60         0x6000      PUSH1 00            0 size
      0x06    0xf3         0xf3        RETURN
      <CODE>
    */

    return abi.encodePacked(
      hex"63",
      uint32(_code.length),
      hex"80_60_0E_60_00_39_60_00_F3",
      _code
    );
  }

  /**
    @notice Returns the size of the code on a given address
    @param _addr Address that may or may not contain code
    @return size of the code on the given `_addr`
  */
  function codeSize(address _addr) internal view returns (uint256 size) {
    assembly { size := extcodesize(_addr) }
  }

  /**
    @notice Returns the code of a given address
    @dev It will fail if `_end < _start`
    @param _addr Address that may or may not contain code
    @param _start number of bytes of code to skip on read
    @param _end index before which to end extraction
    @return oCode read from `_addr` deployed bytecode

    Forked from: https://gist.github.com/KardanovIR/fe98661df9338c842b4a30306d507fbd
  */
  function codeAt(address _addr, uint256 _start, uint256 _end) internal view returns (bytes memory oCode) {
    uint256 csize = codeSize(_addr);
    if (csize == 0) return bytes("");

    if (_start > csize) return bytes("");
    if (_end < _start) revert InvalidCodeAtRange(csize, _start, _end);

    unchecked {
      uint256 reqSize = _end - _start;
      uint256 maxSize = csize - _start;

      uint256 size = maxSize < reqSize ? maxSize : reqSize;

      assembly {
        // allocate output byte array - this could also be done without assembly
        // by using o_code = new bytes(size)
        oCode := mload(0x40)
        // new "memory end" including padding
        mstore(0x40, add(oCode, and(add(add(size, 0x20), 0x1f), not(0x1f))))
        // store length in memory
        mstore(oCode, size)
        // actually retrieve the code, this needs assembly
        extcodecopy(_addr, add(oCode, 0x20), _start, size)
      }
    }
  }
}

// File: Cashier2025/NFT6551/ERC6551Registry.sol




pragma solidity ^0.8.19;




contract BudVilleERC6551Registry is IERC6551Registry {

    function createAccount(
        address accountContract,
        uint256 chainId,
        address nftContract,
        uint256 nftId,
        uint256 salt
    ) external returns (address) {
        bytes memory code = _creationCode(accountContract, chainId, nftContract, nftId, salt);
        address _account = Create2.computeAddress(bytes32(salt), keccak256(code));
        if (_account.code.length != 0) return _account;
        _account = Create2.deploy(0, bytes32(salt), code);
        emit AccountCreated(
            _account,
            accountContract,
            chainId,
            nftContract,
            nftId,
            salt
        );
        return _account;
    }

    function account(
        address accountContract,
        uint256 chainId,
        address nftContract,
        uint256 nftId,
        uint256 salt
    ) external view returns (address) {
        bytes32 bytecodeHash = keccak256(
            _creationCode(accountContract, chainId, nftContract, nftId, salt)
        );

        return Create2.computeAddress(bytes32(salt), bytecodeHash);
    }

    function _creationCode(
        address accountContract_,
        uint256 chainId_,
        address nftContract_,
        uint256 nftId_,
        uint256 salt_
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                accountContract_,
                hex"5af43d82803e903d91602b57fd5bf3",
                abi.encode(salt_, chainId_, nftContract_, nftId_)
            );
    }
}
