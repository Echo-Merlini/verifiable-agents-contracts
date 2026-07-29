// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/AgentMarketEscrow.sol";

/// Minimal ERC-721 with a receiver hook — enough to exercise the escrow's safeTransferFrom paths.
contract MockERC721 {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
    }

    function approve(address spender, uint256 id) external {
        require(ownerOf[id] == msg.sender, "not owner");
        getApproved[id] = spender;
    }

    function safeTransferFrom(address from, address to, uint256 id) external {
        require(ownerOf[id] == from, "wrong from");
        require(msg.sender == from || getApproved[id] == msg.sender, "not approved");
        ownerOf[id] = to;
        getApproved[id] = address(0);
        if (to.code.length > 0) {
            require(
                IERC721Receiver(to).onERC721Received(msg.sender, from, id, "") == IERC721Receiver.onERC721Received.selector,
                "bad receiver"
            );
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

/// A buyer that tries to reenter buy() when it receives the NFT — the guard must block it.
contract ReentrantBuyer {
    AgentMarketEscrow public escrow;
    uint256 public targetId;
    bool public reentryBlocked;

    constructor(AgentMarketEscrow _e) {
        escrow = _e;
    }

    function attack(uint256 id) external payable {
        targetId = id;
        escrow.buy{value: msg.value}(id);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        try escrow.buy{value: 0}(targetId) {
            // should never succeed
        } catch {
            reentryBlocked = true;
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

contract AgentMarketEscrowTest is Test {
    AgentMarketEscrow escrow;
    MockERC721 nft;

    address treasury = address(0xFEE);
    address seller = address(0x5E11E5);
    address buyer = address(0xB0B);
    uint96 feeBps = 250; // 2.5%
    uint256 constant TOKEN = 7;
    uint256 constant PRICE = 1 ether;

    function setUp() public {
        escrow = new AgentMarketEscrow(treasury, feeBps);
        nft = new MockERC721();
        nft.mint(seller, TOKEN);
        vm.deal(buyer, 10 ether);
    }

    function _list() internal returns (uint256 id) {
        vm.startPrank(seller);
        nft.approve(address(escrow), TOKEN);
        id = escrow.list(address(nft), TOKEN, PRICE);
        vm.stopPrank();
    }

    function test_list_escrowsToken() public {
        uint256 id = _list();
        assertEq(nft.ownerOf(TOKEN), address(escrow), "NFT should be in escrow");
        (address s,, uint256 tid, uint256 p, bool active) = escrow.listings(id);
        assertEq(s, seller);
        assertEq(tid, TOKEN);
        assertEq(p, PRICE);
        assertTrue(active);
    }

    function test_buy_paysSellerAndTreasury_transfersNft() public {
        uint256 id = _list();
        uint256 sellerBefore = seller.balance;
        uint256 treasBefore = treasury.balance;

        vm.prank(buyer);
        escrow.buy{value: PRICE}(id);

        uint256 fee = (PRICE * feeBps) / 10_000; // 0.025 ether
        assertEq(nft.ownerOf(TOKEN), buyer, "NFT should go to buyer");
        assertEq(seller.balance - sellerBefore, PRICE - fee, "seller gets price minus fee");
        assertEq(treasury.balance - treasBefore, fee, "treasury gets fee");
        (,,,, bool active) = escrow.listings(id);
        assertFalse(active, "listing closed");
    }

    function test_buy_wrongPayment_reverts() public {
        uint256 id = _list();
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.WrongPayment.selector);
        escrow.buy{value: PRICE - 1}(id);
    }

    function test_buy_twice_reverts() public {
        uint256 id = _list();
        vm.prank(buyer);
        escrow.buy{value: PRICE}(id);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.NotActive.selector);
        escrow.buy{value: PRICE}(id);
    }

    function test_cancel_returnsNft() public {
        uint256 id = _list();
        vm.prank(seller);
        escrow.cancel(id);
        assertEq(nft.ownerOf(TOKEN), seller, "NFT returns to seller");
        (,,,, bool active) = escrow.listings(id);
        assertFalse(active);
    }

    function test_cancel_notSeller_reverts() public {
        uint256 id = _list();
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.NotSeller.selector);
        escrow.cancel(id);
    }

    function test_setPrice_updatesAndGuards() public {
        uint256 id = _list();
        vm.prank(seller);
        escrow.setPrice(id, 2 ether);
        (,,, uint256 p,) = escrow.listings(id);
        assertEq(p, 2 ether);

        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.NotSeller.selector);
        escrow.setPrice(id, 3 ether);

        // buying at the new price works, old price fails
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.WrongPayment.selector);
        escrow.buy{value: 1 ether}(id);
        vm.prank(buyer);
        escrow.buy{value: 2 ether}(id);
        assertEq(nft.ownerOf(TOKEN), buyer);
    }

    function test_list_zeroPrice_reverts() public {
        vm.startPrank(seller);
        nft.approve(address(escrow), TOKEN);
        vm.expectRevert(AgentMarketEscrow.BadPrice.selector);
        escrow.list(address(nft), TOKEN, 0);
        vm.stopPrank();
    }

    function test_constructor_feeTooHigh_reverts() public {
        vm.expectRevert(AgentMarketEscrow.FeeTooHigh.selector);
        new AgentMarketEscrow(treasury, 1001);
    }

    function test_zeroFee_paysFullPriceToSeller() public {
        AgentMarketEscrow free = new AgentMarketEscrow(treasury, 0);
        nft.mint(seller, 99);
        vm.startPrank(seller);
        nft.approve(address(free), 99);
        uint256 id = free.list(address(nft), 99, PRICE);
        vm.stopPrank();
        uint256 sellerBefore = seller.balance;
        vm.prank(buyer);
        free.buy{value: PRICE}(id);
        assertEq(seller.balance - sellerBefore, PRICE, "no fee -> seller gets all");
    }

    function test_reentrancy_blocked() public {
        uint256 id = _list();
        ReentrantBuyer attacker = new ReentrantBuyer(escrow);
        vm.deal(address(attacker), 5 ether);
        attacker.attack{value: PRICE}(id);
        // the buy still completes for the honest path; the reentrant buy() was blocked
        assertTrue(attacker.reentryBlocked(), "reentrant buy must be blocked by the guard");
        assertEq(nft.ownerOf(TOKEN), address(attacker), "NFT delivered to buyer");
    }

    function test_setFeeBps_ownerOnly_andCapped() public {
        escrow.setFeeBps(500);
        assertEq(escrow.feeBps(), 500);
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.NotOwner.selector);
        escrow.setFeeBps(100);
        vm.expectRevert(AgentMarketEscrow.FeeTooHigh.selector);
        escrow.setFeeBps(1001);
    }

    function test_feeChange_appliesToNextSale() public {
        escrow.setFeeBps(1000); // 10%
        uint256 id = _list();
        uint256 sellerBefore = seller.balance;
        uint256 treasBefore = treasury.balance;
        vm.prank(buyer);
        escrow.buy{value: PRICE}(id);
        uint256 fee = (PRICE * 1000) / 10_000;
        assertEq(treasury.balance - treasBefore, fee);
        assertEq(seller.balance - sellerBefore, PRICE - fee);
    }

    function test_setTreasury_ownerOnly() public {
        escrow.setTreasury(address(0xBEEF));
        assertEq(escrow.treasury(), address(0xBEEF));
        vm.prank(buyer);
        vm.expectRevert(AgentMarketEscrow.NotOwner.selector);
        escrow.setTreasury(buyer);
        vm.expectRevert(AgentMarketEscrow.ZeroAddress.selector);
        escrow.setTreasury(address(0));
    }

    function test_transferOwnership() public {
        escrow.transferOwnership(buyer);
        assertEq(escrow.owner(), buyer);
        vm.expectRevert(AgentMarketEscrow.NotOwner.selector);
        escrow.setFeeBps(100);
        vm.prank(buyer);
        escrow.setFeeBps(100);
        assertEq(escrow.feeBps(), 100);
    }

    function test_constructor_zeroTreasury_reverts() public {
        vm.expectRevert(AgentMarketEscrow.ZeroAddress.selector);
        new AgentMarketEscrow(address(0), 250);
    }
}
