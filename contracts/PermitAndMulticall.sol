// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract PermitAndMulticall {
  /**
   * @notice Secp256k1 signature values.
   * @param deadline Timestamp at which the signature expires
   * @param v `v` portion of the signature
   * @param r `r` portion of the signature
   * @param s `s` portion of the signature
   */
  struct Signature {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function multicall(bytes[] calldata _data) external returns (bytes[] memory results) {
    return _multicall(_data);
  }

  function _multicall(bytes[] calldata _data) internal virtual returns (bytes[] memory results) {
    results = new bytes[](_data.length);
    for (uint256 i = 0; i < _data.length; i++) {
      results[i] = Address.functionDelegateCall(address(this), _data[i]);
    }
    return results;
  }

  function _permitAndMulticall(
    IERC20Permit _permitToken,
    address _from,
    uint256 _amount,
    Signature calldata _permitSignature,
    bytes[] calldata _data
  ) internal {
    _permitToken.permit(
      _from,
      address(this),
      _amount,
      _permitSignature.deadline,
      _permitSignature.v,
      _permitSignature.r,
      _permitSignature.s
    );

    _multicall(_data);
  }
}
