pragma solidity ^0.8.0;

import "./Math.sol";

contract IntegralRaise {
  using Math for uint;

  uint public sold;
  uint public targetRaise;
  uint public startPercent;
  uint public targetPrice;
  uint public BASIS_POINTS = 10000;
  uint public slope;

  uint public divisor;

  IERC20 public tokenAddress;
  IERC20 public counterAsset;
  uint public startingAmount;
  uint[] public allocations;

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

  function getPrice() internal view returns (uint) {
    return (targetPrice() * (curve(percentSold(), ) / findDivisor() + startPercent)) / BASIS_POINTS;
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
