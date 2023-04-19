// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IVerifierPool {
    function isVerifier(address verifier) external view returns (bool);

    function getVerifiers() external view returns (address[] memory);

    function getPower(address verifier) external view returns (uint);

    function getTotalPower() external view returns (uint);

    function lastUpdateBlock() external view returns (uint);
}
