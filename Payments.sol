pragma solidity ^0.4.25;

contract ERC20 {
    function transfer(address recipient, uint256 amount)
        public returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        public returns (bool);    
}

contract Payments {
    struct Details {
        bool exists;
        address supplier;
        address purchaser;
        uint256 price;
        uint256 deposit;
        uint64 cancelDeadline;
        uint64 disputeDeadline;
    }

    event Invoice (
        address supplier,
        address purchaser,
        uint256 price,
        uint256 deposit,
        uint64 cancelDeadline,
        uint64 disputeDeadline
    );
    event Payout (
        address supplier,
        address purchaser,
        uint256 price,
        uint256 deposit
    );
    event Cancel (
        address supplier,
        address purchaser,
        uint256 price,
        uint256 deposit
    );    
    event Dispute (
        address arbiter,
        address disputant,
        address supplier,
        address purchaser,
        uint256 price,
        uint256 deposit
    );
    
    modifier onlyPurchaser(bytes32 id) {
        require(msg.sender == details[id].purchaser, "Purchaser only.");
        _;
    }
    
    modifier onlySupplier(bytes32 id) {
        require(msg.sender == details[id].supplier, "Supplier only.");
        _;        
    }
    
    modifier onlyParticipant(bytes32 id) {
        require(
            msg.sender == details[id].supplier ||
            msg.sender == details[id].purchaser,
            "Participant only."
        );
        _;
    }

    modifier completes(bytes32 id) {
        require(details[id].exists, "Unknown id.");
        details[id].exists = false;
        _;
    }
    
    modifier invoices(bytes32 id) {
        require(!details[id].exists, "Given id already exists.");
        _;
        emit Invoice(
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit,
            details[id].cancelDeadline,
            details[id].disputeDeadline
        );
    }
    
    modifier pays(bytes32 id) {
        require(now > details[id].disputeDeadline, "Dispute deadline not met.");
        _;
        emit Payout(
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit
        );
    }
    
    modifier cancels(bytes32 id) {
        require(now < details[id].cancelDeadline, "Cancel deadline passed.");
        _;
        emit Cancel(
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit
        );
    }
    
    modifier disputes(bytes32 id) {
        require(now < details[id].disputeDeadline, "Dispute deadline passed.");
        _;
        emit Dispute(
            msg.sender,
            arbiter,
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit
        );
    }
    
    mapping(bytes32 => Details) public details;
    address public arbiter;
}

contract TokenPayments is Payments {
    ERC20 token;
    uint64 cancelPeriod;
    uint64 disputePeriod;

    constructor(
        address _token,
        address _arbiter,
        uint64 _cancelPeriod,
        uint64 _disputePeriod
    )
        public
    {
        token = ERC20(_token);
        arbiter = _arbiter;
        cancelPeriod = _cancelPeriod;
        disputePeriod = _disputePeriod;
    }
    
    function total(bytes32 id) private view returns (uint256) {
        uint256 value = details[id].price + details[id].deposit;
        assert(value > details[id].price && value > details[id].deposit);
        return value;
    }
    
    function add(uint64 a, uint64 b) private pure returns (uint64) {
        uint64 value = a + b;
        assert(value >= a && value >= b);
        return value;
    }

    function invoice(
        bytes32 id,
        address purchaser,
        uint256 price,
        uint256 deposit,
        uint64 cancelDeadline,
        uint64 disputeDeadline
    )
        public invoices(id)
    {
        require(
            cancelDeadline > add(uint64(now), cancelPeriod),
            "Cancel deadline too soon."
        );
        require(
            disputeDeadline > add(cancelDeadline, disputePeriod),
            "Dispute deadline too soon."
        );
        details[id] = Details(
            true,
            msg.sender,
            purchaser,
            price,
            deposit,
            cancelDeadline,
            disputeDeadline
        );
        require(
            token.transferFrom(purchaser, address(this), total(id)),
            "Transfer failed during invoice."
        );
    }
    
    function cancel(bytes32 id) 
        public onlyPurchaser(id) completes(id) cancels(id)
    {
        require(
            token.transfer(details[id].purchaser, total(id)),
            "Transfer failed during cancel."
        );
    }
    
    function payout(bytes32 id) 
        public onlySupplier(id) completes(id) pays(id)
    {
        require(
            token.transfer(details[id].supplier, details[id].price),
            "Transfer to supplier failed during payout."
        );
        require(
            token.transfer(details[id].purchaser, details[id].deposit),
            "Transfer to purchaser failed during payout."
        );
    }
    
    function dispute(bytes32 id)
        public onlyParticipant(id) completes(id) disputes(id)
    {
        require(
            token.transfer(arbiter, total(id)),
            "Transfer failed during dispute."
        );
    }
}

