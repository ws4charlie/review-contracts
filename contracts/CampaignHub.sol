// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './ERC20Safe.sol';
import '../interfaces/IReviewPool.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

/**
    @title The campaign hub manages all the campaigns.
 */
contract CampaignHub is AccessControl, ERC20Safe {
    // Assuming that all marketplaces have a pattern to locate the product page.
    // www.amazon.com/dp/B0BMB9S1V6
    // www.ebay.com/itm/295471352891
    // www.walmart.com/product/850433920
    // www.homedepot.com/p/311084745
    // www.target.com/p/A-85285926
    // www.bestbuy.com/site/product/6366560.p
    // www.costco.com/.product.100806298.html

    struct Domain {
        string _domain;
        uint16 _utcOffset;
        uint16 _maxRating;
        uint256 _moderation;
    }

    struct Product {
        string _domain;
        string _id;
    }

    struct Campaign {
        address _sponsor;
        string _domain;
        Product[] _products;
        uint256 _bounty;
        uint256 _portion;
        bytes32 _distrib;
        uint256 _claimed;
        uint256 _startAt;
        uint256 _stopAt;
        uint256 _cutoffAt;
        uint256 _closing;
        uint256 _closeAt;
    }

    address public reviewPool;
    address public tokenAddress;
    uint64 public maxCampaignPerProd = 10;
    uint64 public maxProdPerCampaign = 1000;
    uint32 public constant ONE_DAY = 86400;
    uint32 public constant ONE_WEEK = 604800;
    bytes32 public constant DISTRIB_EQUAL = keccak256('DISTRIB_EQUAL');

    // The listed domains
    string[] public domainList;
    mapping(bytes32 => Domain) public domainMap;

    // The total number of campaigns
    uint256 public numCampaigns;

    // The campaigns
    mapping(uint256 => Campaign) public campaigns;

    // reviewID => domain
    mapping(uint256 => bytes32) public review2Domain;

    // sha(domain + id) => campaignID[]
    mapping(bytes32 => uint256[]) public prod2CampaignIDs;

    // sha(domain + id) => reviewRoot => campaignID => reviewID
    mapping(bytes32 => mapping(bytes32 => mapping(uint256 => uint256))) public hasSubmitted2Campaign;

    event CampaignAdded(
        uint256 indexed campaignID,
        string domain,
        Product[] products,
        uint256 bounty,
        uint256 portion,
        bytes32 distrib,
        uint256 startAt,
        uint256 stopAt,
        uint256 closing
    );

    event CampaignTopup(uint256 indexed campaignID, uint256 bounty);
    event CampaignClosed(uint256 indexed campaignID, uint256[] slahedIDs, bool expired);

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 'Not an administator');
        _;
    }

    modifier onlySponsor(uint256 _cmpgnID) {
        require(campaigns[_cmpgnID]._sponsor == msg.sender, 'Not a sponsor');
        _;
    }

    modifier whenClosing(uint256 _cmpgnID) {
        require(campaigns[_cmpgnID]._startAt > 0, 'Campaign not found');
        require(campaigns[_cmpgnID]._closeAt == 0, 'Campaign already closed');
        require(block.timestamp >= campaigns[_cmpgnID]._cutoffAt, 'Wait for review moderation');
        _;
    }

    modifier postClosing(uint256 _cmpgnID) {
        require(campaigns[_cmpgnID]._startAt > 0, 'Campaign not found');
        require(campaigns[_cmpgnID]._closeAt == 0, 'Campaign already closed');
        require(block.timestamp >= campaigns[_cmpgnID]._cutoffAt + campaigns[_cmpgnID]._closing, 'Wait for closing');
        _;
    }

    function domainListed(string memory _domain) public view returns (bool) {
        return bytes(domainMap[sha(_domain)]._domain).length > 0;
    }

    function getDomain(string memory _domain) public view returns (Domain memory) {
        return domainMap[sha(_domain)];
    }

    function isOpen(uint256 _cmpgnID) public view returns (bool) {
        return campaigns[_cmpgnID]._startAt <= block.timestamp && block.timestamp < campaigns[_cmpgnID]._stopAt;
    }

    function submittedB4(bytes32 _prodID, bytes32 _reviewRoot, uint256 _cmpgnID) public view returns (bool) {
        return hasSubmitted2Campaign[_prodID][_reviewRoot][_cmpgnID] > 0;
    }

    function sha(string memory _text) public pure returns (bytes32) {
        return keccak256(bytes(_text));
    }

    function sha(string memory _text1, string memory _text2) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_text1, _text2));
    }

    constructor(
        address _reviewPool,
        address _tokenAddress,
        uint64 _maxCampaignPerProd,
        uint64 _maxProdPerCampaign,
        Domain[] memory _initialDomains
    ) {
        reviewPool = _reviewPool;
        tokenAddress = _tokenAddress;
        maxCampaignPerProd = _maxCampaignPerProd;
        maxProdPerCampaign = _maxProdPerCampaign;
        for (uint256 i = 0; i < _initialDomains.length; i++) {
            if (!domainListed(_initialDomains[i]._domain)) {
                domainList.push(_initialDomains[i]._domain);
                domainMap[sha(_initialDomains[i]._domain)] = _initialDomains[i];
            }
        }
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier validCampaign(
        string memory _domain,
        Product[] memory _products,
        bool _immediate,
        uint256 _bounty,
        uint256 _portion,
        bytes32 _distrib,
        uint256 _startAt,
        uint256 _stopAt,
        uint256 _closing
    ) {
        uint256 startAt = _immediate ? block.timestamp : _startAt;
        require(startAt > block.timestamp, 'Start time must be after now');
        require(_stopAt > startAt, 'Stop time must be after start time');
        require(_bounty > 0, 'Invalid bounty');
        require(_portion > 0, 'Invalid portion');
        require(_distrib == DISTRIB_EQUAL, 'Invalid distribution');
        require(_closing <= ONE_WEEK, 'Closing time too long');

        if (bytes(_domain).length > 0) {
            require(domainListed(_domain), 'Domain not listed');
            require(_products.length == 0, "Don't specify products when creating a domain campaign");
        } else {
            require(_products.length > 0, 'No products specified');
            require(_products.length <= maxProdPerCampaign, 'Too many products');
        }
        _;
    }

    function addProduct(uint256 _cmpgnID, bytes32 _prodID) private returns (bool) {
        for (uint256 i = 0; i < prod2CampaignIDs[_prodID].length; i++) {
            if (prod2CampaignIDs[_prodID][i] == _cmpgnID) {
                return false;
            }
        }
        prod2CampaignIDs[_prodID].push(_cmpgnID);
        return true;
    }

    function loadProducts(uint256 _cmpgnID, Campaign storage campaign) private {
        uint256 count = 0;
        for (uint256 i = 0; i < campaign._products.length; i++) {
            bytes32 prodID = sha(campaign._products[i]._domain, campaign._products[i]._id);
            require(domainListed(campaign._products[i]._domain), 'Product domain not listed');
            require(bytes(campaign._products[i]._id).length > 0, 'Product ID cannot be empty');
            if (addProduct(_cmpgnID, prodID)) {
                campaign._products[count++] = campaign._products[i];
            }
        }
        for (uint256 i = 0; i < campaign._products.length - count; i++) {
            campaign._products.pop();
        }
    }

    function newCampaign(
        string memory _domain,
        Product[] memory _products,
        bool _immediate,
        uint256 _bounty,
        uint256 _portion,
        bytes32 _distrib,
        uint256 _startAt,
        uint256 _stopAt,
        uint256 _closing
    )
        external
        payable
        validCampaign(_domain, _products, _immediate, _bounty, _portion, _distrib, _startAt, _stopAt, _closing)
    {
        uint256 cmpgnID = numCampaigns++;
        uint256 startAt = _immediate ? block.timestamp : _startAt;

        Campaign storage campaign = campaigns[cmpgnID];
        campaign._products = _products;
        loadProducts(cmpgnID, campaign);
        campaign._sponsor = msg.sender;
        campaign._bounty = _bounty;
        campaign._portion = _portion;
        campaign._distrib = _distrib;
        campaign._startAt = startAt;
        campaign._stopAt = _stopAt;
        campaign._cutoffAt = _stopAt;
        campaign._closing = _closing;

        lockERC20(tokenAddress, msg.sender, address(this), _bounty);
        _products = campaign._products;
        emit CampaignAdded(cmpgnID, _domain, _products, _bounty, _portion, _distrib, startAt, _stopAt, _closing);
    }

    function topupCampaign(uint256 _cmpgnID, uint256 _bounty) external payable onlySponsor(_cmpgnID) {
        require(campaigns[_cmpgnID]._stopAt > block.timestamp, 'Campaign is stopped');

        campaigns[_cmpgnID]._bounty += _bounty;
        lockERC20(tokenAddress, msg.sender, address(this), _bounty);
        emit CampaignTopup(_cmpgnID, _bounty);
    }

    function submitReview(string calldata _domain, string calldata _id, bytes32 _rootHash, bytes32 _headHash) external {
        bytes32 prodID = sha(_domain, _id);
        uint256[] memory cmpgnIDs = prod2CampaignIDs[prodID];
        require(cmpgnIDs.length > 0, 'No campaign found for this product');
        require(_rootHash != bytes32(0), 'Invalid root hash');
        require(_headHash != bytes32(0), 'Invalid head hash');
        require(_rootHash != _headHash, 'Review root hash must be different from head hash');

        for (uint256 i = 0; i < cmpgnIDs.length; i++) {
            if (isOpen(cmpgnIDs[i]) && !submittedB4(prodID, _rootHash, cmpgnIDs[i])) {
                IReviewPool iPool = IReviewPool(reviewPool);
                uint256 reviewID = iPool.submit(cmpgnIDs[i], prodID, _rootHash, _headHash);
                review2Domain[reviewID] = sha(_domain);
                hasSubmitted2Campaign[prodID][_rootHash][cmpgnIDs[i]] = reviewID;
                if (block.timestamp + domainMap[sha(_domain)]._moderation > campaigns[cmpgnIDs[i]]._cutoffAt) {
                    campaigns[cmpgnIDs[i]]._cutoffAt = block.timestamp + domainMap[sha(_domain)]._moderation;
                }
            }
        }
    }

    function verifyReview(
        uint256 _reviewID,
        bytes32 _bodyHash,
        uint16 _rating,
        uint256 _appearedAt,
        bytes32 _mktReviewID
    ) external {
        Domain memory domain = domainMap[review2Domain[_reviewID]];
        require(_rating > 0 && _rating <= domain._maxRating, 'Invalid rating');
        require(_mktReviewID != bytes32(0), 'Invalid market review ID');
        IReviewPool iPool = IReviewPool(reviewPool);
        iPool.verify(_reviewID, _bodyHash, _rating, _appearedAt, _mktReviewID);
    }

    function closeCampaign(
        uint256 _cmpgnID,
        uint256[] calldata _slashIDs
    ) external onlySponsor(_cmpgnID) whenClosing(_cmpgnID) {
        Campaign storage campaign = campaigns[_cmpgnID];
        IReviewPool iPool = IReviewPool(reviewPool);
        uint256 remain = iPool.close(
            _cmpgnID,
            campaign._bounty,
            campaign._portion,
            campaign._distrib,
            tokenAddress,
            _slashIDs
        );
        campaign._claimed = campaign._bounty - remain;
        campaign._bounty = remain;
        campaign._closeAt = block.timestamp;
        releaseERC20(tokenAddress, campaign._sponsor, remain);

        emit CampaignClosed(_cmpgnID, _slashIDs, false);
    }

    function expireCampaign(uint256 _cmpgnID) external postClosing(_cmpgnID) {
        Campaign storage campaign = campaigns[_cmpgnID];
        IReviewPool iPool = IReviewPool(reviewPool);
        uint256 remain = iPool.close(
            _cmpgnID,
            campaign._bounty,
            campaign._portion,
            campaign._distrib,
            tokenAddress,
            new uint256[](0)
        );
        campaign._claimed = campaign._bounty - remain;
        campaign._bounty = remain;
        campaign._closeAt = block.timestamp;
        releaseERC20(tokenAddress, campaign._sponsor, remain);

        emit CampaignClosed(_cmpgnID, new uint256[](0), true);
    }
}
