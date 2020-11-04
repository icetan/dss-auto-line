pragma solidity ^0.6.7;

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function Line() external view returns (uint256);
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
}

contract DssAutoLine {
    mapping (address => uint256)    public  wards;
    VatLike                         public  immutable   vat;
    mapping (bytes32 => Ilk)        public              ilks;

    struct Ilk {
        uint256 line; // Max ceiling possible
        uint256 on;   // Check if ilk is enabled
        uint256 ttl;  // Min time to pass before a new increase
        uint256 gap;  // Max Value between current debt and line to be set
        uint256 last; // Last time the ceiling was increased compared to its previous value
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
    event Exec(bytes32 indexed ilk, uint256 line, uint256 lineNew);

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    constructor(address vat_) public {
        vat = VatLike(vat_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "DssAutoLine/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "line") ilks[ilk].line = data;
        else if (what == "ttl") ilks[ilk].ttl = data;
        else if (what == "gap") ilks[ilk].gap = data;
        else if (what == "on") ilks[ilk].on = data;
        else revert("DssAutoLine/file-unrecognized-param");
        emit File(ilk, what, data);
    }

    function exec(bytes32 ilk) public {
        // Check the ilk ins enabled
        require(ilks[ilk].on == 1, "DssAutoLine/ilk-not-enabled");

        (uint256 Art, uint256 rate,, uint256 line,) = vat.ilks(ilk);
        // Calculate collateral debt
        uint256 debt = mul(Art, rate);

        // Calculate new line based on the minimum between the maximum line and actual collateral debt + gap
        uint256 lineNew = min(add(debt, ilks[ilk].gap), ilks[ilk].line);

        // Check the ceiling is not increasing or enough time has passed since last increase
        require(lineNew <= line || now >= add(ilks[ilk].last, ilks[ilk].ttl), "DssAutoLine/no-min-time-passed");

        // Set collateral debt ceiling
        vat.file(ilk, "line", lineNew);
        // Set general debt ceiling
        vat.file("Line", add(sub(vat.Line(), line), lineNew));

        // Update last if it was an increment in the debt ceiling
        if (lineNew > line) ilks[ilk].last = now;

        emit Exec(ilk, line, lineNew);
    }
}
