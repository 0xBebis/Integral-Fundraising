pragma solidity ^0.8.0;

import "./Math.sol";

contract IntegralFundraising {
  using Math for uint;

  uint public sold;
  uint public targetRaise;
  uint public startPercent;
  uint public targetPrice;

  uint public BASIS_POINTS = 10000;
  uint public slope;

  uint public divisor;

  IERC20 public asset;
  IERC20 public counterAsset;
  uint public startingAmount;

  struct License {
    uint threshold;
    uint limit;
  }

  struct Allocation {
    uint remaining;
    bool activated;
  }
  mapping(address => License) public licenses;
  mapping(address => mapping(uint => Allocation)) public allocations;
  mapping(address => uint) public tokensPurchased;

  ERC721Enumerable[] public supportedTokens;

  /*
   + lower number = tighter slope
  */

  constructor(
    address _tokenAddress,
    address _counterAsset,
    uint[] calldata _allocations,
    uint _startPercent,
    uint _targetRaise,
    uint _targetPrice,
    uint _slope
  ) {
    require(_slope <= 5, "no point");
    tokenAddress = IERC20(tokenAddress);
    counterAsset = IERC20(counterAsset);
    allocations = _allocations;
    startPercent = _startPercent;
    targetRaise = _targetRaise;
    targetPrice = _targetPrice;
    slope = _slope;
  }

  function buy(uint amount, address NFT, uint index) external view returns (bool) {
    require(licenses[NFT].limit > 0, "buy: this NFT is not eligible for whitelist");
    requre(getPrice() >= licenses[NFT].threshold, "buy: you cannot buy yet");
    _buy(amount, NFT, index);
    tokensPurchased[msg.sender] += amount;
    return true;
  }

  function _buy(uint amount, address NFT, uint index) internal view returns (bool) {
    Allocation storage alloc = allocations[NFT][index];
    if (!alloc.activated) {
      activate(NFT, index, amount);
    } else {
      require(alloc.remaining >= amount);
      alloc.remaining -= amount;
    }

    uint cost = getPrice() * amount / BASIS_POINTS;
    counterAsset.transferFrom(msg.sender, address(this), cost);
    asset.transfer(msg.sender, amount);
  }

  function activate(address NFT, uint index, uint amount) internal returns (true) {
    require(amount <= licenses[NFT].limit, "activate: amount too high");
    Allocation storage alloc = allocations[NFT][index];
    alloc.remaining = licenses[NFT][index].limit - amount;
    alloc.activated = true;
    return true;
  }

  function getPrice() internal view returns (uint) {
    return (targetPrice() * (baseCurve(percentSold()) / findDivisor() + startPercent));
  }

  function percentRaised() internal view returns (uint) {
    return raised() * BASIS_POINTS / targetRaise;
  }

  function percentSold() internal view returns (uint) {
    return sold() * BASIS_POINTS / startingAmount;
  }

  function baseCurve(uint n) internal view returns (uint) {
    uint curve = n ** 2;
    if (slope > 0) {
      for (uint i = 0; i <= slope; i++) {
        curve = curve * Math.sqrt(n);
      }
    }
    return curve;
  }

  function sold() internal view returns (uint) {
    return fundsForSale - tokenAddress.balanceOf(address(this));
  }

  function raised() internal view returns (uint) {
    return counterAsset.balanceOf(address(this));
  }

  function findDivisor(uint n) internal pure returns (uint) {
    return (baseCurve(BASIS_POINTS)) / BASIS_POINTS + n;
  }

  function targetPrice() internal view returns (uint) {
    return modify(targetPrice);
  }

  function modify(uint n) internal pure returns (n) { }

}
