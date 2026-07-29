// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title AgentMarketEscrow
/// @notice A non-custodial-settlement marketplace escrow for buying and selling agent NFTs
///         (e.g. GenesisAgentRegistry agents) so owners can speculate.
///
///         Custodial-while-listed: the seller escrows the agent NFT into this contract on `list()`,
///         so a listing can never go stale against a token the seller quietly moved. `buy()` is
///         atomic — it pays the seller (minus an optional protocol fee) and transfers the NFT to the
///         buyer in one transaction; `cancel()` returns the NFT to the seller.
///
///         Recomputable by design: every state change emits an event, so the full listing/sale
///         history re-derives from logs with nothing trusted in between. A `Sold` receipt is an
///         EXISTENCE fact — "this exact sale happened, unaltered" — and is NOT a correctness verdict
///         about the agent. A marketplace surfacing these MUST NOT fuse a sale (or a listing) with a
///         review/reputation signal into one "green"; they are separate typed facts.
///
///         Entitlements (MCPEntitlementRegistry) are bound to the agent tokenId and travel with the
///         NFT on transfer, so a bought agent arrives with the capabilities it was listed carrying.
contract AgentMarketEscrow {
    struct Listing {
        address seller;
        address nft;
        uint256 tokenId;
        uint256 price; // wei
        bool active;
    }

    /// @notice contract owner — can tune the protocol fee + treasury.
    address public owner;
    /// @notice protocol fee recipient.
    address public treasury;
    /// @notice protocol fee in basis points, capped at 10% (1000).
    uint96 public feeBps;

    uint256 public nextId = 1;
    mapping(uint256 => Listing) public listings;

    uint256 private _lock = 1;

    event Listed(uint256 indexed id, address indexed seller, address indexed nft, uint256 tokenId, uint256 price);
    event PriceChanged(uint256 indexed id, uint256 oldPrice, uint256 newPrice);
    event Sold(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint256 fee
    );
    event Cancelled(uint256 indexed id);
    event FeeChanged(uint96 oldBps, uint96 newBps);
    event TreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    error NotSeller();
    error NotActive();
    error BadPrice();
    error WrongPayment();
    error FeeTooHigh();
    error PayFailed();
    error Reentrancy();
    error NotOwner();
    error ZeroAddress();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _treasury, uint96 _feeBps) {
        if (_feeBps > 1000) revert FeeTooHigh();
        if (_treasury == address(0)) revert ZeroAddress();
        owner = msg.sender;
        treasury = _treasury;
        feeBps = _feeBps;
    }

    // ── owner controls ──────────────────────────────────────────────────────────
    /// @notice Set the protocol fee (basis points, ≤ 10%). Applies to future sales; the fee actually
    ///         taken is always emitted in each `Sold` event, so it stays transparent/recomputable.
    function setFeeBps(uint96 newBps) external onlyOwner {
        if (newBps > 1000) revert FeeTooHigh();
        emit FeeChanged(feeBps, newBps);
        feeBps = newBps;
    }

    /// @notice Set the protocol fee recipient.
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Transfer ownership of the fee controls.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice List an agent NFT for sale. The caller must have approved this escrow for the token
    ///         first; the NFT is pulled into escrow (custodial while listed).
    /// @return id the new listing id.
    function list(address nft, uint256 tokenId, uint256 price) external nonReentrant returns (uint256 id) {
        if (price == 0) revert BadPrice();
        id = nextId++;
        listings[id] = Listing({seller: msg.sender, nft: nft, tokenId: tokenId, price: price, active: true});
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);
        emit Listed(id, msg.sender, nft, tokenId, price);
    }

    /// @notice Change the asking price of an active listing (seller only).
    function setPrice(uint256 id, uint256 newPrice) external {
        Listing storage l = listings[id];
        if (!l.active) revert NotActive();
        if (l.seller != msg.sender) revert NotSeller();
        if (newPrice == 0) revert BadPrice();
        uint256 old = l.price;
        l.price = newPrice;
        emit PriceChanged(id, old, newPrice);
    }

    /// @notice Buy a listed agent. Pays the seller (minus fee) and transfers the NFT to the buyer.
    ///         Checks-effects-interactions + a reentrancy guard; exact payment required.
    function buy(uint256 id) external payable nonReentrant {
        Listing storage l = listings[id];
        if (!l.active) revert NotActive();
        if (msg.value != l.price) revert WrongPayment();

        l.active = false; // effect before interactions

        uint256 fee = (msg.value * feeBps) / 10_000;
        uint256 toSeller = msg.value - fee;

        IERC721(l.nft).safeTransferFrom(address(this), msg.sender, l.tokenId);
        _pay(l.seller, toSeller);
        if (fee > 0) _pay(treasury, fee);

        emit Sold(id, msg.sender, l.seller, l.nft, l.tokenId, l.price, fee);
    }

    /// @notice Cancel an active listing; the NFT returns to the seller (seller only).
    function cancel(uint256 id) external nonReentrant {
        Listing storage l = listings[id];
        if (!l.active) revert NotActive();
        if (l.seller != msg.sender) revert NotSeller();
        l.active = false;
        IERC721(l.nft).safeTransferFrom(address(this), l.seller, l.tokenId);
        emit Cancelled(id);
    }

    function _pay(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert PayFailed();
    }

    /// @notice ERC-721 receiver hook so the escrow can accept `safeTransferFrom`.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
