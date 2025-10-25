# Guía de Uso - Sistema de Escrow con Pagos Escalonados

## Contratos Creados

### 1. ERC20Token.sol
Token de prueba con función faucet para facilitar el testing.

**Características:**
- Token ERC20 estándar (nombre: "ExpoToken", símbolo: "EXPO")
- Función `faucet()` que entrega 1000 tokens cada hora
- Supply inicial de 1,000,000 tokens para el deployer

### 2. OrderEscrow.sol
Sistema de escrow con pagos escalonados: 70% al enviar, 30% al confirmar entrega.

---

## Flujo de Uso Completo

### Paso 1: Desplegar Contratos

```javascript
// 1. Desplegar el token
const token = await ERC20Token.deploy();
await token.deployed();

// 2. Desplegar el escrow pasando la dirección del token
const escrow = await OrderEscrow.deploy(token.address);
await escrow.deployed();
```

### Paso 2: Cliente Obtiene Tokens (Testing)

```javascript
// El cliente solicita tokens del faucet
await token.connect(cliente).faucet();

// Verificar si puede usar el faucet
const [canUse, timeRemaining] = await token.canUseFaucet(clienteAddress);
```

### Paso 3: Cliente Crea una Orden

```javascript
// 1. Aprobar al contrato de escrow para gastar tokens
const amount = ethers.utils.parseEther("1000"); // 1000 tokens
await token.connect(cliente).approve(escrow.address, amount);

// 2. Crear la orden
const tx = await escrow.connect(cliente).createOrder(
  providerAddress,  // Dirección del proveedor/repartidor
  amount           // Monto total
);

// 3. Obtener el orderId del evento
const receipt = await tx.wait();
const event = receipt.events.find(e => e.event === 'OrderCreated');
const orderId = event.args.orderId;
```

### Paso 4: Proveedor Marca como Enviado (Libera 70%)

```javascript
// El proveedor marca la orden como enviada
// Esto automáticamente libera el 70% del pago
await escrow.connect(proveedor).markAsShipped(orderId);

// Verificar balance del proveedor
const balance = await token.balanceOf(proveedorAddress);
// Balance ahora tiene 700 tokens (70% de 1000)
```

### Paso 5: Cliente Confirma Entrega (Libera 30%)

```javascript
// El cliente confirma que recibió la orden
// Esto libera el 30% restante al proveedor
await escrow.connect(cliente).confirmDelivery(orderId);

// Proveedor ahora tiene el 100% del pago
```

---

## Funciones de Vista para el Frontend

### Obtener Detalles de una Orden

```javascript
const order = await escrow.getOrder(orderId);
console.log({
  orderId: order.orderId,
  customer: order.customer,
  provider: order.provider,
  totalAmount: ethers.utils.formatEther(order.totalAmount),
  status: order.status, // 0=Created, 1=Shipped, 2=Delivered, 3=Disputed, 4=Refunded
  deadline: new Date(order.deadline * 1000)
});
```

### Verificar Acciones Disponibles

```javascript
const [status, canShip, canConfirm, canRefund, canDispute] =
  await escrow.getOrderActions(orderId);

// Mostrar botones en el frontend según los booleanos
if (canShip) {
  // Mostrar botón "Marcar como Enviado"
}
if (canConfirm) {
  // Mostrar botón "Confirmar Entrega"
}
if (canDispute) {
  // Mostrar botón "Disputar Orden"
}
if (canRefund) {
  // Mostrar botón "Solicitar Reembolso"
}
```

### Ver Resumen de Pagos

```javascript
const [total, paid, remaining, first, second] =
  await escrow.getPaymentSummary(orderId);

console.log({
  totalAmount: ethers.utils.formatEther(total),
  paidToProvider: ethers.utils.formatEther(paid),
  remainingInEscrow: ethers.utils.formatEther(remaining),
  firstPaymentReleased: first,  // true/false
  secondPaymentReleased: second // true/false
});
```

### Listar Órdenes de un Usuario

```javascript
// Órdenes del cliente
const customerOrderIds = await escrow.getCustomerOrders(clienteAddress);

// Órdenes del proveedor
const providerOrderIds = await escrow.getProviderOrders(proveedorAddress);

// Cargar detalles de cada orden
for (const orderId of customerOrderIds) {
  const order = await escrow.getOrder(orderId);
  // Mostrar en la UI
}
```

---

## Manejo de Casos Especiales

### Solicitar Reembolso (Si no se envió a tiempo)

```javascript
// Si el proveedor NO marcó como enviado antes del deadline (7 días)
// El cliente puede solicitar reembolso completo
try {
  await escrow.connect(cliente).requestRefund(orderId);
  // Cliente recupera el 100% del monto
} catch (error) {
  // Error: DeadlineNotReached - aún no pasó el plazo
}
```

### Disputar una Orden

```javascript
// Si el cliente recibe la orden pero hay un problema
// Puede disputar ANTES de confirmar entrega
try {
  await escrow.connect(cliente).disputeOrder(orderId);
  // Orden marcada como disputada
  // Fondos restantes (30%) quedan bloqueados en el contrato
} catch (error) {
  // Error: InvalidOrderState o DeadlinePassed
}
```

---

## Estados de la Orden

```javascript
enum OrderStatus {
  Created = 0,    // Orden creada, fondos depositados
  Shipped = 1,    // Enviado, 70% liberado
  Delivered = 2,  // Entregado, 100% liberado
  Disputed = 3,   // En disputa, fondos bloqueados
  Refunded = 4    // Reembolsado al cliente
}
```

---

## Errores Personalizados

Los contratos usan custom errors para ahorrar gas:

```javascript
// ERC20Token
error FaucetAmountTooHigh()
error FaucetCooldownActive(uint256 timeRemaining)

// OrderEscrow
error InvalidAmount()
error InvalidProvider()
error OrderNotFound()
error Unauthorized()
error InvalidOrderState()
error DeadlineNotReached()
error DeadlinePassed()
error TransferFailed()
```

Manejar en el frontend:

```javascript
try {
  await token.connect(user).faucet();
} catch (error) {
  if (error.message.includes('FaucetCooldownActive')) {
    // Extraer timeRemaining del error
    // Mostrar: "Debes esperar X minutos"
  }
}
```

---

## Eventos para Escuchar en Tiempo Real

```javascript
// Escuchar nuevas órdenes
escrow.on("OrderCreated", (orderId, customer, provider, amount, deadline) => {
  console.log(`Nueva orden #${orderId} creada`);
  // Actualizar UI
});

// Escuchar cuando se marca como enviado
escrow.on("OrderShipped", (orderId, paymentReleased, timestamp) => {
  console.log(`Orden #${orderId} enviada, ${paymentReleased} liberados`);
  // Actualizar UI
});

// Escuchar confirmación de entrega
escrow.on("OrderDelivered", (orderId, paymentReleased, timestamp) => {
  console.log(`Orden #${orderId} entregada, ${paymentReleased} liberados`);
  // Actualizar UI
});
```

---

## Ejemplo de Componente React

```jsx
import { useState, useEffect } from 'react';
import { ethers } from 'ethers';

function OrderCard({ orderId, escrowContract }) {
  const [order, setOrder] = useState(null);
  const [actions, setActions] = useState({});

  useEffect(() => {
    loadOrderData();
  }, [orderId]);

  async function loadOrderData() {
    const orderData = await escrowContract.getOrder(orderId);
    const [status, canShip, canConfirm, canRefund, canDispute] =
      await escrowContract.getOrderActions(orderId);

    setOrder(orderData);
    setActions({ canShip, canConfirm, canRefund, canDispute });
  }

  async function handleShip() {
    const tx = await escrowContract.markAsShipped(orderId);
    await tx.wait();
    loadOrderData(); // Refrescar
  }

  async function handleConfirm() {
    const tx = await escrowContract.confirmDelivery(orderId);
    await tx.wait();
    loadOrderData();
  }

  return (
    <div className="order-card">
      <h3>Orden #{orderId.toString()}</h3>
      <p>Monto: {ethers.utils.formatEther(order.totalAmount)} EXPO</p>
      <p>Estado: {['Creada', 'Enviada', 'Entregada', 'Disputada', 'Reembolsada'][order.status]}</p>

      {actions.canShip && (
        <button onClick={handleShip}>Marcar como Enviado</button>
      )}
      {actions.canConfirm && (
        <button onClick={handleConfirm}>Confirmar Entrega</button>
      )}
      {actions.canDispute && (
        <button onClick={() => escrowContract.disputeOrder(orderId)}>Disputar</button>
      )}
      {actions.canRefund && (
        <button onClick={() => escrowContract.requestRefund(orderId)}>Solicitar Reembolso</button>
      )}
    </div>
  );
}
```

---

## Características Técnicas Implementadas

1. **Patrón CEI (Checks-Effects-Interactions)**: Todas las funciones siguen este patrón para evitar reentrancy attacks.

2. **Custom Errors**: Ahorra gas comparado con strings en `require()`.

3. **SafeERC20**: Uso de SafeERC20 de OpenZeppelin para transferencias seguras.

4. **Inmutabilidad**: El token de pago es immutable una vez desplegado.

5. **Eventos**: Todos los cambios de estado emiten eventos para que el frontend los capture.

6. **Funciones de Vista**: Funciones específicas para facilitar la integración con el frontend sin necesidad de parsear eventos.

7. **Deadline automático**: 7 días por defecto para completar una orden.

---

## Seguridad

- Solo el cliente puede confirmar entrega o disputar
- Solo el proveedor puede marcar como enviado
- Los fondos están protegidos en el contrato hasta que se cumplan las condiciones
- No hay función de retiro directo, solo a través del flujo establecido
- Deadlines protegen contra órdenes abandonadas
