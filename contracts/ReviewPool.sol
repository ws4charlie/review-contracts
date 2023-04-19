// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './ERC20Safe.sol';
import '../interfaces/IVerifierPool.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

/**
    @title The review pool manages all the reviews.
 */
contract ReviewPool is ERC20Safe {
    enum Status {
        None,
        Submitted,
        Verified,
        Slashed,
        Rewarded,
        Missed,
        Expired
    }

    struct Review {
        address _reviewer;
        uint256[] _cmpgnIDs;
        bytes32 _prodHash;
        bytes32 _rootHash;
        bytes32 _headHash;
        bytes32 _bodyHash;
        uint256 _submittedAt;
        uint256 _reward;
        Status _status;
    }

    struct Metadata {
        uint16 _rating;
        uint256 _appearedAt;
        bytes32 _mktReviewID;
    }

    struct Poll {
        bytes32 opinion;
        mapping(bytes32 => uint) opinion2Power;
        mapping(bytes32 => Metadata) opinion2Meta;
        mapping(address => bytes32) voter2Opinion;
    }

    uint32 public constant ONE_DAY = 86400;
    bytes32 public constant DISTRIB_EQUAL = keccak256('DISTRIB_EQUAL');

    address public gate;

    IVerifierPool public vrfyPool;

    // last verifier pool update block number
    uint256 public lastUpdateBlock;

    // campaignID => Review count
    mapping(uint256 => uint256) public campaign2ReviewCount;

    // reviewID => Review
    mapping(uint256 => Review) public reviews;

    // reviewID => Poll
    mapping(uint256 => Poll) public polls;

    // reviewID => verifier => opinion
    mapping(uint256 => mapping(address => bytes32)) public hasVotedSubmittion;

    // reviewID => opinions
    mapping(uint256 => bytes32[]) public review2Opinions;

    event ReviewSubmitted(
        uint256 indexed campaignID,
        uint256 indexed reviewID,
        bytes32 indexed prodHash,
        bytes32 rootHash,
        bytes32 headHash,
        uint256 submittedAt
    );

    event ReviewVote(uint256 indexed reviewID, address indexed verifier, bytes32 bodyHash, bytes32 mktReviewID);

    event ReviewVerified(uint256 indexed reviewID, bytes32 _bodyHash, bytes32 _mktReviewID);

    modifier onlyGate() {
        require(msg.sender == gate, 'sender must be gate contract');
        _;
    }

    modifier exist(uint256 _reviewID) {
        require(reviews[_reviewID]._status != Status.None, 'Review does not exist');
        _;
    }

    function getProdHash(uint256 _reviewID) public view returns (bytes32) {
        return reviews[_reviewID]._prodHash;
    }

    constructor(IVerifierPool _verifyPool) {
        vrfyPool = _verifyPool;
    }

    function submit(
        uint256 _cmpgnID,
        bytes32 _prodHash,
        bytes32 _rootHash,
        bytes32 _headHash
    ) external onlyGate returns (uint256 reviewID) {
        reviewID = ++campaign2ReviewCount[_cmpgnID];
        Review storage review = reviews[reviewID];
        review._cmpgnIDs.push(_cmpgnID);
        if (review._status == Status.None) {
            review._prodHash = _prodHash;
            review._rootHash = _rootHash;
            review._headHash = _headHash;
            review._submittedAt = block.timestamp;
            review._status = Status.Submitted;
        }
        emit ReviewSubmitted(_cmpgnID, reviewID, _prodHash, _rootHash, _headHash, block.number);
    }

    function verify(
        uint256 _reviewID,
        bytes32 _bodyHash,
        uint16 _rating,
        uint256 _appearedAt,
        bytes32 _mktReviewID
    ) external onlyGate exist(_reviewID) {
        Poll storage poll = polls[_reviewID];
        Review storage review = reviews[_reviewID];
        require(vrfyPool.isVerifier(msg.sender), 'Not a verifier');
        require(poll.voter2Opinion[msg.sender] == bytes32(0), 'Already voted');
        require(review._status == Status.Submitted, 'Review is not in Submitted status');
        require(review._rootHash == keccak256(abi.encodePacked(review._headHash, _bodyHash)), 'Hash mismatch');
        if (review._bodyHash == bytes32(0)) {
            review._bodyHash = _bodyHash;
        }

        poll.opinion = bytes32(0);
        bytes32 opinion = keccak256(abi.encodePacked(_rating, _appearedAt, _mktReviewID));
        poll.voter2Opinion[msg.sender] = opinion;
        poll.opinion2Meta[opinion] = Metadata(_rating, _appearedAt, _mktReviewID);

        address[] memory voters = vrfyPool.getVerifiers();
        for (uint256 i = 0; i < voters.length; i++) {
            opinion = poll.voter2Opinion[voters[i]];
            if (opinion != bytes32(0)) {
                poll.opinion2Power[opinion] = 0;
            }
        }
        // update leading opinion
        uint256 leadPower = 0;
        for (uint256 i = 0; i < voters.length; i++) {
            opinion = poll.voter2Opinion[voters[i]];
            if (opinion != bytes32(0)) {
                poll.opinion2Power[opinion] += vrfyPool.getPower(voters[i]);
                if (poll.opinion2Power[opinion] > leadPower) {
                    poll.opinion = opinion;
                    leadPower = poll.opinion2Power[opinion];
                }
            }
        }
        emit ReviewVote(_reviewID, msg.sender, _bodyHash, _mktReviewID);

        // winning opinion gets more than 2/3 of votes
        if (leadPower >= (vrfyPool.getTotalPower() * 2) / 3) {
            Metadata memory meta = poll.opinion2Meta[poll.opinion];
            require(meta._appearedAt > review._submittedAt, 'Review appeared before submission!');
            review._status = Status.Verified;
            emit ReviewVerified(_reviewID, _bodyHash, _mktReviewID);
        }
    }

    function close(
        uint256 _cmpgnID,
        uint256 _bounty,
        uint256 _portion,
        bytes32 _distrib,
        address _token,
        uint256[] calldata _reviewIDs
    ) external onlyGate returns (uint256) {
        // slash reviews
        for (uint256 i = 0; i < _reviewIDs.length; i++) {
            require(_reviewIDs[i] <= campaign2ReviewCount[_cmpgnID], 'Invalid review ID to slash');
            if (reviews[_reviewIDs[i]]._status == Status.Verified) {
                reviews[_reviewIDs[i]]._status = Status.Slashed;
            }
        }

        // reward reviews according to distribution
        uint256 reviewCount = campaign2ReviewCount[_cmpgnID];
        if (_distrib == DISTRIB_EQUAL) {
            for (uint256 i = 1; i <= reviewCount; i++) {
                Review storage review = reviews[i];
                if (review._status == Status.Verified) {
                    if (_bounty >= _portion) {
                        releaseERC20(_token, review._reviewer, _portion);
                        review._reward = _portion;
                        review._status = Status.Rewarded;
                        _bounty -= _portion;
                    } else {
                        review._status = Status.Missed;
                    }
                } else {
                    review._status = Status.Expired;
                }
            }
        }
        return _bounty;
    }
}
