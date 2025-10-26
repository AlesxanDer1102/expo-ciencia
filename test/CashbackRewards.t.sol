// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CashbackRewards.sol";
import "../src/ERC20Token.sol";

contract CashbackRewardsTest is Test {
    CashbackRewards public rewards;
    ERC20Token public token;

    // Direcciones de prueba
    address public owner = address(0x1);
    address public cliente = address(0x2);
    address public comerciante = address(0x3);
    
    // Montos de prueba
    uint256 public constant SALDO_INICIAL = 10000 * 10**18;
    uint256 public constant MONTO_PAGO = 100 * 10**18;
    uint256 public constant COMPRA_MINIMA = 10 * 10**18;

    function setUp() public {
        // Desplegar token de prueba
        vm.startPrank(owner);
        token = new ERC20Token(); // El constructor ya mintea 1,000,000 tokens al deployer (owner)
        
        // Desplegar contrato de recompensas
        rewards = new CashbackRewards(address(token));
        
        // Asignar tokens al cliente y comerciante
        token.transfer(cliente, SALDO_INICIAL);
        token.transfer(comerciante, SALDO_INICIAL);
        
        // Transferir fondos restantes al contrato de recompensas
        uint256 remainingBalance = token.balanceOf(owner);
        token.transfer(address(rewards), remainingBalance);
        
        // Aprobar que el contrato de recompensas pueda gastar tokens del cliente
        vm.stopPrank();
        
        vm.startPrank(cliente);
        token.approve(address(rewards), type(uint256).max);
        vm.stopPrank();
    }

    // Función auxiliar para realizar un pago
    function _hacerPago(uint256 monto) private {
        vm.prank(cliente);
        rewards.processPayment(monto, comerciante);
    }

    // 1. Prueba de configuración inicial
    function test_ConfiguracionInicial() public view{
        assertEq(address(rewards.paymentToken()), address(token));
        (bool isActive, uint256 cashbackRate, uint256 pointsRate, uint256 minPurchase) = rewards.rewardConfig();
        assertTrue(isActive);
        assertEq(cashbackRate, 500); // 5%
        assertEq(pointsRate, 100);   // 100 puntos por token
        assertEq(minPurchase, COMPRA_MINIMA);
    }

    // 2. Prueba de pago exitoso con cashback
    function test_ProcesarPago() public {
        uint256 saldoInicialCliente = token.balanceOf(cliente);
        uint256 saldoInicialComerciante = token.balanceOf(comerciante);
        uint256 saldoInicialContrato = token.balanceOf(address(rewards));
        
        // Realizar un pago de 100 tokens
        uint256 montoPago = 100 * 10**18;
        uint256 cashbackEsperado = (montoPago * 500) / 10000; // 5%
        uint256 montoComerciante = montoPago - cashbackEsperado;
        uint256 puntosEsperados = (montoPago * 100) / 10**18; // 100 puntos por token
        
        vm.prank(cliente);
        rewards.processPayment(montoPago, comerciante);
        
        // Verificar saldos
        assertEq(token.balanceOf(cliente), saldoInicialCliente - montoPago, "Saldo incorrecto del cliente");
        assertEq(token.balanceOf(comerciante), saldoInicialComerciante + montoComerciante, "Saldo incorrecto del comerciante");
        
        // Verificar que el cashback se envió al contrato de recompensas
        // El cashback esperado es 5% de 100 tokens = 5 tokens
        // Sumamos el cashback esperado al saldo inicial del contrato
        uint256 saldoEsperadoContrato = saldoInicialContrato + cashbackEsperado;
        assertEq(token.balanceOf(address(rewards)), saldoEsperadoContrato, "Monto de cashback incorrecto en el contrato de recompensas");
        
        // Verificar puntos
        assertEq(rewards.userPoints(cliente), puntosEsperados);
    }

    // 3. Prueba de compra mínima
    function test_CompraMinima() public {
        uint256 debajoDelMinimo = 5 * 10**18; // Por debajo del mínimo de 10 tokens
        
        vm.prank(cliente);
        vm.expectRevert("Purchase amount below minimum");
        rewards.processPayment(debajoDelMinimo, comerciante);
    }

    // 4. Prueba de canje de puntos
    function test_CanjearPuntos() public {
        // Primero hacer un pago para ganar puntos
        _hacerPago(MONTO_PAGO);
        
        uint256 puntos = rewards.userPoints(cliente);
        uint256 saldoInicial = token.balanceOf(cliente);
        
        // Canjear puntos
        vm.prank(cliente);
        rewards.redeemPoints(puntos);
        
        // Verificar que se descontaron los puntos
        assertEq(rewards.userPoints(cliente), 0);
        
        // Verificar que se transfirieron los tokens (puntos / pointsRate * 10^18)
        uint256 tokensEsperados = (puntos * 10**18) / 100;
        assertEq(token.balanceOf(cliente), saldoInicial + tokensEsperados);
    }

    // 5. Prueba de canje con puntos insuficientes
    function test_CanjearPuntosInsuficientes() public {
        vm.prank(cliente);
        vm.expectRevert("Insufficient points");
        rewards.redeemPoints(1); // Intentar canjear sin tener puntos
    }

    // 6. Prueba de actualización de configuración
    function test_ActualizarConfiguracion() public {
        vm.prank(owner);
        rewards.setRewardConfig(
            false,  // isActive
            1000,   // 10% cashback
            200,    // 200 puntos por token
            20 * 10**18  // 20 tokens de compra mínima
        );
        
        (bool isActive, uint256 cashbackRate, uint256 pointsRate, uint256 minPurchase) = rewards.rewardConfig();
        
        assertEq(isActive, false);
        assertEq(cashbackRate, 1000);
        assertEq(pointsRate, 200);
        assertEq(minPurchase, 20 * 10**18);
    }

    // 7. Prueba de retiro de fondos por el propietario
    function test_RetirarFondos() public {
        // Hacer un pago para tener fondos en el contrato
        _hacerPago(MONTO_PAGO);
        
        uint256 saldoContrato = token.balanceOf(address(rewards));
        uint256 saldoInicialPropietario = token.balanceOf(owner);
        
        vm.prank(owner);
        rewards.withdrawFunds(saldoContrato);
        
        // Verificar saldos después del retiro
        assertEq(token.balanceOf(address(rewards)), 0);
        assertEq(token.balanceOf(owner), saldoInicialPropietario + saldoContrato);
    }

    // 8. Prueba de pago cuando las recompensas están inactivas
    function test_PagoRecompensasInactivas() public {
        // Desactivar recompensas
        vm.prank(owner);
        rewards.setRewardConfig(false, 500, 100, COMPRA_MINIMA);
        
        // Intentar hacer un pago
        vm.prank(cliente);
        vm.expectRevert("Rewards program is not active");
        rewards.processPayment(MONTO_PAGO, comerciante);
    }

    // 9. Prueba de múltiples pagos y canjes
    function test_MultiplesPagosYCanjes() public {
        uint256 totalPuntos = 0;
        
        // Hacer 3 pagos
        for (uint i = 0; i < 3; i++) {
            _hacerPago(MONTO_PAGO);
            totalPuntos += (MONTO_PAGO * 100) / 10**18;
            assertEq(rewards.userPoints(cliente), totalPuntos);
        }
        
        // Canjear la mitad de los puntos
        uint256 puntosACanjear = totalPuntos / 2;
        uint256 tokensEsperados = (puntosACanjear * 10**18) / 100;
        uint256 saldoInicial = token.balanceOf(cliente);
        
        vm.prank(cliente);
        rewards.redeemPoints(puntosACanjear);
        
        assertEq(rewards.userPoints(cliente), totalPuntos - puntosACanjear);
        assertEq(token.balanceOf(cliente), saldoInicial + tokensEsperados);
    }

    // 10. Prueba de pago con dirección cero
    function test_PagoDireccionCero() public {
        vm.prank(cliente);
        vm.expectRevert("Invalid recipient address");
        rewards.processPayment(MONTO_PAGO, address(0));
    }

    // 11. Prueba de pago con monto exacto al mínimo
    function test_PagoExactoMinimo() public {
        // Obtener el valor mínimo de compra del contrato
        (, , , uint256 minPurchase) = rewards.rewardConfig();
        
        // Verificar que el pago mínimo sea mayor que cero
        assertTrue(minPurchase > 0, "Minimum purchase should be greater than zero");
        
        // Realizar el pago con el monto mínimo
        uint256 saldoInicial = token.balanceOf(cliente);
        
        vm.prank(cliente);
        rewards.processPayment(minPurchase, comerciante);
        
        // Verificar que se registraron los puntos correctamente
        uint256 puntosEsperados = (minPurchase * 100) / 10**18;
        assertEq(rewards.userPoints(cliente), puntosEsperados, "Points not calculated correctly");
        
        // Verificar que se transfirieron los fondos correctamente
        uint256 saldoEsperado = saldoInicial - minPurchase;
        assertEq(token.balanceOf(cliente), saldoEsperado, "Incorrect token balance after payment");
    }

    // 12. Prueba de pago con tasa máxima de cashback
    function test_PagoMaximoCashback() public {
        // Establecer tasa de cashback al máximo (10%)
        vm.prank(owner);
        rewards.setRewardConfig(true, 1000, 100, COMPRA_MINIMA);
        
        uint256 saldoInicialComerciante = token.balanceOf(comerciante);
        
        vm.prank(cliente);
        rewards.processPayment(MONTO_PAGO, comerciante);
        
        // El comerciante debería recibir el 90% del pago (10% de cashback)
        uint256 montoEsperadoComerciante = (MONTO_PAGO * 9000) / 10000;
        assertEq(token.balanceOf(comerciante), saldoInicialComerciante + montoEsperadoComerciante);
    }

    // 13. Prueba de pago con alta tasa de puntos
    function test_PagoAltaTasaPuntos() public {
        // Establecer tasa de puntos a 1000 (10x la predeterminada)
        vm.prank(owner);
        rewards.setRewardConfig(true, 500, 1000, COMPRA_MINIMA);
        
        vm.prank(cliente);
        rewards.processPayment(MONTO_PAGO, comerciante);
        
        // Debería ganar 1000 puntos por token
        uint256 puntosEsperados = (MONTO_PAGO * 1000) / 10**18;
        assertEq(rewards.userPoints(cliente), puntosEsperados);
    }
}