// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IReviewPool {
    function submit(uint256 _cID, bytes32 _prodHash, bytes32 _rootHash, bytes32 _headHash) external returns (uint256);

    function verify(
        uint256 _reviewID,
        bytes32 _bodyHash,
        uint16 _rating,
        uint256 _appearedAt,
        bytes32 _mktReviewID
    ) external;

    function close(
        uint256 _cmpgnID,
        uint256 _bounty,
        uint256 _portion,
        bytes32 _distrib,
        address _token,
        uint256[] calldata _reviewIDs
    ) external returns (uint256);
}
