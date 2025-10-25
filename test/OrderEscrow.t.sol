// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OrderEscrow.sol";
import "../src/ERC20Token.sol";

contract OrderEscrowTest is Test {
    OrderEscrow public escrow;
    ERC20Token public token;

    address public customer = address(0x1);
    address public provider = address(0x2);
    address public other = address(0x3);

    uint256 public constant ORDER_AMOUNT = 1000 * 10**18;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed customer,
        address indexed provider,
        uint256 totalAmount,
        uint256 deadline
    );

    event OrderShipped(
        uint256 indexed orderId,
        uint256 paymentReleased,
        uint256 timestamp
    );

    event OrderDelivered(
        uint256 indexed orderId,
        uint256 paymentReleased,
        uint256 timestamp
    );

    event OrderRefunded(
        uint256 indexed orderId,
        uint256 refundAmount,
        uint256 timestamp
    );

    event OrderDisputed(
        uint256 indexed orderId,
        uint256 timestamp
    );

    function setUp() public {
        // Desplegar contratos
        token = new ERC20Token();
        escrow = new OrderEscrow(address(token));

        // Dar tokens al cliente usando el faucet
        vm.startPrank(customer);
        token.faucet();
        vm.stopPrank();

        // Etiquetar direcciones para mejor debugging
        vm.label(customer, "Customer");
        vm.label(provider, "Provider");
        vm.label(address(escrow), "Escrow");
        vm.label(address(token), "Token");
    }

    // ============================================
    // TESTS DE CREACIÓN DE ORDEN
    // ============================================

    function test_CreateOrder() public {
        vm.startPrank(customer);

        // Aprobar tokens al escrow
        token.approve(address(escrow), ORDER_AMOUNT);

        // Crear orden
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(1, customer, provider, ORDER_AMOUNT, block.timestamp + 7 days);

        uint256 orderId = escrow.createOrder(provider, ORDER_AMOUNT);

        vm.stopPrank();

        // Verificar que se creó correctamente
        assertEq(orderId, 1);

        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(order.orderId, 1);
        assertEq(order.customer, customer);
        assertEq(order.provider, provider);
        assertEq(order.totalAmount, ORDER_AMOUNT);
        assertEq(order.firstPayment, 700 * 10**18); // 70%
        assertEq(order.secondPayment, 300 * 10**18); // 30%
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Created));
        assertFalse(order.firstPaymentReleased);
        assertFalse(order.secondPaymentReleased);

        // Verificar que los fondos están en el escrow
        assertEq(token.balanceOf(address(escrow)), ORDER_AMOUNT);
        assertEq(token.balanceOf(customer), 0);
    }

    function test_CreateOrder_RevertIf_InvalidProvider() public {
        vm.startPrank(customer);
        token.approve(address(escrow), ORDER_AMOUNT);

        vm.expectRevert(OrderEscrow.InvalidProvider.selector);
        escrow.createOrder(address(0), ORDER_AMOUNT);

        vm.stopPrank();
    }

    function test_CreateOrder_RevertIf_InvalidAmount() public {
        vm.startPrank(customer);
        token.approve(address(escrow), ORDER_AMOUNT);

        vm.expectRevert(OrderEscrow.InvalidAmount.selector);
        escrow.createOrder(provider, 0);

        vm.stopPrank();
    }

    function test_CreateOrder_RevertIf_CustomerIsProvider() public {
        vm.startPrank(customer);
        token.approve(address(escrow), ORDER_AMOUNT);

        vm.expectRevert(OrderEscrow.InvalidProvider.selector);
        escrow.createOrder(customer, ORDER_AMOUNT);

        vm.stopPrank();
    }

    // ============================================
    // TESTS DE MARCAR COMO ENVIADO
    // ============================================

    function test_MarkAsShipped() public {
        // Crear orden primero
        uint256 orderId = _createOrder();

        // Proveedor marca como enviado
        vm.startPrank(provider);

        vm.expectEmit(true, false, false, true);
        emit OrderShipped(orderId, 700 * 10**18, block.timestamp);

        escrow.markAsShipped(orderId);
        vm.stopPrank();

        // Verificar estado
        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Shipped));
        assertTrue(order.firstPaymentReleased);
        assertFalse(order.secondPaymentReleased);

        // Verificar que el proveedor recibió el 70%
        assertEq(token.balanceOf(provider), 700 * 10**18);
        assertEq(token.balanceOf(address(escrow)), 300 * 10**18);
    }

    function test_MarkAsShipped_RevertIf_Unauthorized() public {
        uint256 orderId = _createOrder();

        vm.startPrank(other);
        vm.expectRevert(OrderEscrow.Unauthorized.selector);
        escrow.markAsShipped(orderId);
        vm.stopPrank();
    }

    function test_MarkAsShipped_RevertIf_OrderNotFound() public {
        vm.startPrank(provider);
        vm.expectRevert(OrderEscrow.OrderNotFound.selector);
        escrow.markAsShipped(999);
        vm.stopPrank();
    }

    function test_MarkAsShipped_RevertIf_InvalidState() public {
        uint256 orderId = _createOrder();

        // Marcar como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        // Intentar marcar de nuevo
        vm.startPrank(provider);
        vm.expectRevert(OrderEscrow.InvalidOrderState.selector);
        escrow.markAsShipped(orderId);
        vm.stopPrank();
    }

    function test_MarkAsShipped_RevertIf_DeadlinePassed() public {
        uint256 orderId = _createOrder();

        // Avanzar tiempo más allá del deadline
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(provider);
        vm.expectRevert(OrderEscrow.DeadlinePassed.selector);
        escrow.markAsShipped(orderId);
        vm.stopPrank();
    }

    // ============================================
    // TESTS DE CONFIRMAR ENTREGA
    // ============================================

    function test_ConfirmDelivery() public {
        uint256 orderId = _createOrder();

        // Marcar como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        // Cliente confirma entrega
        vm.startPrank(customer);

        vm.expectEmit(true, false, false, true);
        emit OrderDelivered(orderId, 300 * 10**18, block.timestamp);

        escrow.confirmDelivery(orderId);
        vm.stopPrank();

        // Verificar estado
        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Delivered));
        assertTrue(order.firstPaymentReleased);
        assertTrue(order.secondPaymentReleased);

        // Verificar que el proveedor recibió el 100%
        assertEq(token.balanceOf(provider), ORDER_AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_ConfirmDelivery_RevertIf_Unauthorized() public {
        uint256 orderId = _createOrder();
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        vm.startPrank(other);
        vm.expectRevert(OrderEscrow.Unauthorized.selector);
        escrow.confirmDelivery(orderId);
        vm.stopPrank();
    }

    function test_ConfirmDelivery_RevertIf_NotShipped() public {
        uint256 orderId = _createOrder();

        vm.startPrank(customer);
        vm.expectRevert(OrderEscrow.InvalidOrderState.selector);
        escrow.confirmDelivery(orderId);
        vm.stopPrank();
    }

    // ============================================
    // TESTS DE REEMBOLSO
    // ============================================

    function test_RequestRefund() public {
        uint256 orderId = _createOrder();

        // Avanzar tiempo más allá del deadline
        vm.warp(block.timestamp + 8 days);

        // Cliente solicita reembolso
        vm.startPrank(customer);

        vm.expectEmit(true, false, false, true);
        emit OrderRefunded(orderId, ORDER_AMOUNT, block.timestamp);

        escrow.requestRefund(orderId);
        vm.stopPrank();

        // Verificar estado
        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Refunded));

        // Verificar que el cliente recuperó sus fondos
        assertEq(token.balanceOf(customer), ORDER_AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_RequestRefund_RevertIf_Unauthorized() public {
        uint256 orderId = _createOrder();
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(other);
        vm.expectRevert(OrderEscrow.Unauthorized.selector);
        escrow.requestRefund(orderId);
        vm.stopPrank();
    }

    function test_RequestRefund_RevertIf_DeadlineNotReached() public {
        uint256 orderId = _createOrder();

        vm.startPrank(customer);
        vm.expectRevert(OrderEscrow.DeadlineNotReached.selector);
        escrow.requestRefund(orderId);
        vm.stopPrank();
    }

    function test_RequestRefund_RevertIf_AlreadyShipped() public {
        uint256 orderId = _createOrder();

        // Marcar como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        // Avanzar tiempo
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(customer);
        vm.expectRevert(OrderEscrow.InvalidOrderState.selector);
        escrow.requestRefund(orderId);
        vm.stopPrank();
    }

    // ============================================
    // TESTS DE DISPUTA
    // ============================================

    function test_DisputeOrder() public {
        uint256 orderId = _createOrder();

        // Marcar como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        // Cliente disputa
        vm.startPrank(customer);

        vm.expectEmit(true, false, false, false);
        emit OrderDisputed(orderId, block.timestamp);

        escrow.disputeOrder(orderId);
        vm.stopPrank();

        // Verificar estado
        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Disputed));

        // Verificar que el 30% sigue en el escrow
        assertEq(token.balanceOf(address(escrow)), 300 * 10**18);
    }

    function test_DisputeOrder_RevertIf_Unauthorized() public {
        uint256 orderId = _createOrder();
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        vm.startPrank(other);
        vm.expectRevert(OrderEscrow.Unauthorized.selector);
        escrow.disputeOrder(orderId);
        vm.stopPrank();
    }

    function test_DisputeOrder_RevertIf_NotShipped() public {
        uint256 orderId = _createOrder();

        vm.startPrank(customer);
        vm.expectRevert(OrderEscrow.InvalidOrderState.selector);
        escrow.disputeOrder(orderId);
        vm.stopPrank();
    }

    function test_DisputeOrder_RevertIf_DeadlinePassed() public {
        uint256 orderId = _createOrder();

        vm.prank(provider);
        escrow.markAsShipped(orderId);

        // Avanzar tiempo más allá del deadline
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(customer);
        vm.expectRevert(OrderEscrow.DeadlinePassed.selector);
        escrow.disputeOrder(orderId);
        vm.stopPrank();
    }

    // ============================================
    // TESTS DE FUNCIONES DE VISTA
    // ============================================

    function test_GetOrderActions_Created() public {
        uint256 orderId = _createOrder();

        (
            OrderEscrow.OrderStatus status,
            bool canShip,
            bool canConfirm,
            bool canRefund,
            bool canDispute
        ) = escrow.getOrderActions(orderId);

        assertEq(uint(status), uint(OrderEscrow.OrderStatus.Created));
        assertTrue(canShip);
        assertFalse(canConfirm);
        assertFalse(canRefund);
        assertFalse(canDispute);
    }

    function test_GetOrderActions_Shipped() public {
        uint256 orderId = _createOrder();
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        (
            OrderEscrow.OrderStatus status,
            bool canShip,
            bool canConfirm,
            bool canRefund,
            bool canDispute
        ) = escrow.getOrderActions(orderId);

        assertEq(uint(status), uint(OrderEscrow.OrderStatus.Shipped));
        assertFalse(canShip);
        assertTrue(canConfirm);
        assertFalse(canRefund);
        assertTrue(canDispute);
    }

    function test_GetOrderActions_AfterDeadline() public {
        uint256 orderId = _createOrder();
        vm.warp(block.timestamp + 8 days);

        (
            OrderEscrow.OrderStatus status,
            bool canShip,
            bool canConfirm,
            bool canRefund,
            bool canDispute
        ) = escrow.getOrderActions(orderId);

        assertEq(uint(status), uint(OrderEscrow.OrderStatus.Created));
        assertFalse(canShip);
        assertFalse(canConfirm);
        assertTrue(canRefund);
        assertFalse(canDispute);
    }

    function test_GetPaymentSummary() public {
        uint256 orderId = _createOrder();

        // Estado inicial
        (
            uint256 total,
            uint256 paid,
            uint256 remaining,
            bool first,
            bool second
        ) = escrow.getPaymentSummary(orderId);

        assertEq(total, ORDER_AMOUNT);
        assertEq(paid, 0);
        assertEq(remaining, ORDER_AMOUNT);
        assertFalse(first);
        assertFalse(second);

        // Después de marcar como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);

        (total, paid, remaining, first, second) = escrow.getPaymentSummary(orderId);
        assertEq(paid, 700 * 10**18);
        assertEq(remaining, 300 * 10**18);
        assertTrue(first);
        assertFalse(second);

        // Después de confirmar entrega
        vm.prank(customer);
        escrow.confirmDelivery(orderId);

        (total, paid, remaining, first, second) = escrow.getPaymentSummary(orderId);
        assertEq(paid, ORDER_AMOUNT);
        assertEq(remaining, 0);
        assertTrue(first);
        assertTrue(second);
    }

    function test_GetCustomerOrders() public {
        // Crear múltiples órdenes
        _createOrder();
        _createOrder();
        _createOrder();

        uint256[] memory orders = escrow.getCustomerOrders(customer);
        assertEq(orders.length, 3);
        assertEq(orders[0], 1);
        assertEq(orders[1], 2);
        assertEq(orders[2], 3);
    }

    function test_GetProviderOrders() public {
        // Crear múltiples órdenes
        _createOrder();
        _createOrder();
        _createOrder();

        uint256[] memory orders = escrow.getProviderOrders(provider);
        assertEq(orders.length, 3);
        assertEq(orders[0], 1);
        assertEq(orders[1], 2);
        assertEq(orders[2], 3);
    }

    // ============================================
    // TESTS DE FLUJO COMPLETO
    // ============================================

    function test_CompleteFlow_HappyPath() public {
        // 1. Cliente crea orden
        uint256 orderId = _createOrder();
        assertEq(token.balanceOf(customer), 0);
        assertEq(token.balanceOf(provider), 0);
        assertEq(token.balanceOf(address(escrow)), ORDER_AMOUNT);

        // 2. Proveedor marca como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);
        assertEq(token.balanceOf(provider), 700 * 10**18);
        assertEq(token.balanceOf(address(escrow)), 300 * 10**18);

        // 3. Cliente confirma entrega
        vm.prank(customer);
        escrow.confirmDelivery(orderId);
        assertEq(token.balanceOf(provider), ORDER_AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);

        // Verificar estado final
        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Delivered));
    }

    function test_CompleteFlow_RefundPath() public {
        // 1. Cliente crea orden
        uint256 orderId = _createOrder();

        // 2. Proveedor no envía a tiempo
        vm.warp(block.timestamp + 8 days);

        // 3. Cliente solicita reembolso
        vm.prank(customer);
        escrow.requestRefund(orderId);

        // Verificar que el cliente recuperó todo
        assertEq(token.balanceOf(customer), ORDER_AMOUNT);
        assertEq(token.balanceOf(provider), 0);
        assertEq(token.balanceOf(address(escrow)), 0);

        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Refunded));
    }

    function test_CompleteFlow_DisputePath() public {
        // 1. Cliente crea orden
        uint256 orderId = _createOrder();

        // 2. Proveedor marca como enviado
        vm.prank(provider);
        escrow.markAsShipped(orderId);
        uint256 providerBalanceAfterShip = token.balanceOf(provider);

        // 3. Cliente disputa
        vm.prank(customer);
        escrow.disputeOrder(orderId);

        // Verificar que el proveedor solo tiene el 70%
        assertEq(token.balanceOf(provider), providerBalanceAfterShip);
        assertEq(token.balanceOf(address(escrow)), 300 * 10**18);

        OrderEscrow.Order memory order = escrow.getOrder(orderId);
        assertEq(uint(order.status), uint(OrderEscrow.OrderStatus.Disputed));
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _createOrder() internal returns (uint256) {
        vm.startPrank(customer);

        // Dar más tokens si es necesario
        if (token.balanceOf(customer) < ORDER_AMOUNT) {
            token.faucet();
        }

        token.approve(address(escrow), ORDER_AMOUNT);
        uint256 orderId = escrow.createOrder(provider, ORDER_AMOUNT);

        vm.stopPrank();

        return orderId;
    }
}
