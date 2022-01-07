pragma solidity ^0.8.0;

contract Memento is ERC721 {

  //pid to nonce
  mapping (uint => uint) public nonces;

  function createId(uint pid) internal returns (uint256) {
    uint id = uint256(keccack256(abi.encodePacked(pid, nonces[pid]));
    nonces[pid]++;
    return id;
  }

  function mint(address to, uint pid) internal returns (bool) {
    uint id = createId(pid);
    _safeMint(to, id);
    return true;
  }



}
