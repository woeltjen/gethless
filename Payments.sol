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
    
    modifier exists(bytes32 id) {
        require(details[id].exists);
        _;
    }

    modifier onlyPurchaser(bytes32 id) {
        require(msg.sender == details[id].purchaser);
        _;
    }
    
    modifier onlySupplier(bytes32 id) {
        require(msg.sender == details[id].supplier);
        _;        
    }
    
    modifier onlyParticipant(bytes32 id) {
        require(msg.sender == details[id].supplier || 
            msg.sender == details[id].purchaser);
        _;
    }
    
    modifier canPayout(bytes32 id) {
        require(now > details[id].disputeDeadline);
        _;
    }
    
    modifier canDispute(bytes32 id) {
        require(now < details[id].disputeDeadline);
        _;
    }
    
    modifier canCancel(bytes32 id) {
        require(now < details[id].cancelDeadline);
        _;
    }
    
    modifier terminates(bytes32 id) {
        details[id].exists = false;
        _;
    }
    
    modifier invoices(bytes32 id) {
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
        _;
        emit Payout(
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit
        );
    }
    
    modifier cancels(bytes32 id) {
        _;
        emit Cancel(
            details[id].supplier,
            details[id].purchaser,
            details[id].price,
            details[id].deposit
        );
    }
    
    modifier disputes(bytes32 id) {
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
    
    mapping(bytes32 => Details) details;
    address arbiter;
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
    
    function invoice(
        bytes32 id,
        address purchaser,
        uint256 price,
        uint256 deposit,
        uint64 cancelDeadline,
        uint64 disputeDeadline
    )
        public
        invoices(id)
    {
        require(!details[id].exists);
        require(cancelDeadline > (now + cancelPeriod));
        require(disputeDeadline > (cancelDeadline + disputePeriod));
        details[id] = Details(
            true,
            msg.sender,
            purchaser,
            price,
            deposit,
            cancelDeadline,
            disputeDeadline
        );
        require(token.transferFrom(purchaser, address(this), total(id)));
    }
    
    function cancel(bytes32 id) 
        public
        exists(id) onlyPurchaser(id) canCancel(id) terminates(id) cancels(id)
    {
        require(token.transfer(details[id].purchaser, total(id)));
    }
    
    function payout(bytes32 id) 
        public
        exists(id) onlySupplier(id) canPayout(id) terminates(id) pays(id)
    {
        require(token.transfer(details[id].supplier, details[id].price));
        require(token.transfer(details[id].purchaser, details[id].deposit));
    }
    
    function dispute(bytes32 id)
        public
        exists(id) onlyParticipant(id) canDispute(id) terminates(id) disputes(id) 
    {
        require(token.transfer(arbiter, total(id)));
    }
}

