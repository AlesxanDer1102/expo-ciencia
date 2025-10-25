// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title OrderEscrow - Sistema de pagos escalonados para pedidos
/// @notice Contrato de escrow que libera pagos en etapas: 70% al enviar, 30% al confirmar entrega
contract OrderEscrow {
    using SafeERC20 for IERC20;

    // Custom Errors
    error InvalidAmount();
    error InvalidProvider();
    error OrderNotFound();
    error Unauthorized();
    error InvalidOrderState();
    error DeadlineNotReached();
    error DeadlinePassed();
    error TransferFailed();

    // Enums
    enum OrderStatus {
        Created,        // Orden creada, fondos depositados
        Shipped,        // Proveedor marcó como enviado, 70% liberado
        Delivered,      // Cliente confirmó entrega, 30% liberado
        Disputed,       // Orden en disputa
        Refunded        // Fondos devueltos al cliente
    }

    // Structs
    struct Order {
        uint256 orderId;
        address customer;
        address provider;
        uint256 totalAmount;
        uint256 firstPayment;      // 70%
        uint256 secondPayment;     // 30%
        OrderStatus status;
        uint256 createdAt;
        uint256 shippedAt;
        uint256 deadline;          // Plazo para confirmar entrega
        bool firstPaymentReleased;
        bool secondPaymentReleased;
    }

    // State variables
    IERC20 public immutable paymentToken;
    uint256 public orderCounter;
    uint256 public constant FIRST_PAYMENT_PCT = 70;
    uint256 public constant SECOND_PAYMENT_PCT = 30;
    uint256 public constant DEFAULT_DELIVERY_DEADLINE = 7 days;

    // Mappings
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public customerOrders;
    mapping(address => uint256[]) public providerOrders;

    // Events
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

    constructor(address _paymentToken) {
        if (_paymentToken == address(0)) revert InvalidProvider();
        paymentToken = IERC20(_paymentToken);
    }

    /// @notice Crear una nueva orden
    /// @param provider Dirección del proveedor/repartidor
    /// @param amount Monto total de la orden
    /// @return orderId ID de la orden creada
    function createOrder(
        address provider,
        uint256 amount
    ) external returns (uint256 orderId) {
        // Checks
        if (provider == address(0)) revert InvalidProvider();
        if (amount == 0) revert InvalidAmount();
        if (provider == msg.sender) revert InvalidProvider();

        // Effects
        orderId = ++orderCounter;

        uint256 firstPayment = (amount * FIRST_PAYMENT_PCT) / 100;
        uint256 secondPayment = amount - firstPayment; // Asegura que sume exactamente el total

        orders[orderId] = Order({
            orderId: orderId,
            customer: msg.sender,
            provider: provider,
            totalAmount: amount,
            firstPayment: firstPayment,
            secondPayment: secondPayment,
            status: OrderStatus.Created,
            createdAt: block.timestamp,
            shippedAt: 0,
            deadline: block.timestamp + DEFAULT_DELIVERY_DEADLINE,
            firstPaymentReleased: false,
            secondPaymentReleased: false
        });

        customerOrders[msg.sender].push(orderId);
        providerOrders[provider].push(orderId);

        emit OrderCreated(orderId, msg.sender, provider, amount, orders[orderId].deadline);

        // Interactions
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Proveedor marca la orden como enviada, libera 70%
    /// @param orderId ID de la orden
    function markAsShipped(uint256 orderId) external {
        Order storage order = orders[orderId];

        // Checks
        if (order.orderId == 0) revert OrderNotFound();
        if (msg.sender != order.provider) revert Unauthorized();
        if (order.status != OrderStatus.Created) revert InvalidOrderState();
        if (block.timestamp > order.deadline) revert DeadlinePassed();

        // Effects
        order.status = OrderStatus.Shipped;
        order.shippedAt = block.timestamp;
        order.firstPaymentReleased = true;

        emit OrderShipped(orderId, order.firstPayment, block.timestamp);

        // Interactions
        paymentToken.safeTransfer(order.provider, order.firstPayment);
    }

    /// @notice Cliente confirma entrega, libera 30% restante
    /// @param orderId ID de la orden
    function confirmDelivery(uint256 orderId) external {
        Order storage order = orders[orderId];

        // Checks
        if (order.orderId == 0) revert OrderNotFound();
        if (msg.sender != order.customer) revert Unauthorized();
        if (order.status != OrderStatus.Shipped) revert InvalidOrderState();

        // Effects
        order.status = OrderStatus.Delivered;
        order.secondPaymentReleased = true;

        emit OrderDelivered(orderId, order.secondPayment, block.timestamp);

        // Interactions
        paymentToken.safeTransfer(order.provider, order.secondPayment);
    }

    /// @notice Cliente solicita reembolso si no se marcó como enviado antes del deadline
    /// @param orderId ID de la orden
    function requestRefund(uint256 orderId) external {
        Order storage order = orders[orderId];

        // Checks
        if (order.orderId == 0) revert OrderNotFound();
        if (msg.sender != order.customer) revert Unauthorized();
        if (order.status != OrderStatus.Created) revert InvalidOrderState();
        if (block.timestamp <= order.deadline) revert DeadlineNotReached();

        // Effects
        order.status = OrderStatus.Refunded;
        uint256 refundAmount = order.totalAmount;

        emit OrderRefunded(orderId, refundAmount, block.timestamp);

        // Interactions
        paymentToken.safeTransfer(order.customer, refundAmount);
    }

    /// @notice Cliente marca orden como disputada (después de enviada pero antes de confirmar)
    /// @param orderId ID de la orden
    function disputeOrder(uint256 orderId) external {
        Order storage order = orders[orderId];

        // Checks
        if (order.orderId == 0) revert OrderNotFound();
        if (msg.sender != order.customer) revert Unauthorized();
        if (order.status != OrderStatus.Shipped) revert InvalidOrderState();
        if (block.timestamp > order.deadline) revert DeadlinePassed();

        // Effects
        order.status = OrderStatus.Disputed;

        emit OrderDisputed(orderId, block.timestamp);

        // Nota: En disputa, los fondos restantes quedan bloqueados
        // Se puede implementar un mecanismo de resolución de disputas aquí
    }

    /// @notice Obtener detalles completos de una orden
    /// @param orderId ID de la orden
    /// @return order Datos de la orden
    function getOrder(uint256 orderId) external view returns (Order memory order) {
        order = orders[orderId];
        if (order.orderId == 0) revert OrderNotFound();
    }

    /// @notice Obtener todas las órdenes de un cliente
    /// @param customer Dirección del cliente
    /// @return orderIds Array de IDs de órdenes
    function getCustomerOrders(address customer) external view returns (uint256[] memory) {
        return customerOrders[customer];
    }

    /// @notice Obtener todas las órdenes de un proveedor
    /// @param provider Dirección del proveedor
    /// @return orderIds Array de IDs de órdenes
    function getProviderOrders(address provider) external view returns (uint256[] memory) {
        return providerOrders[provider];
    }

    /// @notice Verificar el estado de una orden de forma amigable para el frontend
    /// @param orderId ID de la orden
    /// @return status Estado actual
    /// @return canShip Si el proveedor puede marcar como enviado
    /// @return canConfirm Si el cliente puede confirmar entrega
    /// @return canRefund Si el cliente puede solicitar reembolso
    /// @return canDispute Si el cliente puede disputar
    function getOrderActions(uint256 orderId) external view returns (
        OrderStatus status,
        bool canShip,
        bool canConfirm,
        bool canRefund,
        bool canDispute
    ) {
        Order memory order = orders[orderId];
        if (order.orderId == 0) revert OrderNotFound();

        status = order.status;
        canShip = (order.status == OrderStatus.Created && block.timestamp <= order.deadline);
        canConfirm = (order.status == OrderStatus.Shipped);
        canRefund = (order.status == OrderStatus.Created && block.timestamp > order.deadline);
        canDispute = (order.status == OrderStatus.Shipped && block.timestamp <= order.deadline);
    }

    /// @notice Obtener resumen de pagos de una orden
    /// @param orderId ID de la orden
    function getPaymentSummary(uint256 orderId) external view returns (
        uint256 totalAmount,
        uint256 paidToProvider,
        uint256 remainingInEscrow,
        bool firstPaymentReleased,
        bool secondPaymentReleased
    ) {
        Order memory order = orders[orderId];
        if (order.orderId == 0) revert OrderNotFound();

        totalAmount = order.totalAmount;
        paidToProvider = 0;

        if (order.firstPaymentReleased) {
            paidToProvider += order.firstPayment;
        }
        if (order.secondPaymentReleased) {
            paidToProvider += order.secondPayment;
        }

        remainingInEscrow = totalAmount - paidToProvider;
        firstPaymentReleased = order.firstPaymentReleased;
        secondPaymentReleased = order.secondPaymentReleased;
    }
}
