// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ERC20Token.sol";
import "../src/OrderEscrow.sol";

/// @title Deploy - Script de despliegue para ERC20Token y OrderEscrow
/// @notice Despliega primero el token ERC20 y luego el contrato OrderEscrow
contract Deploy is Script {
    function run() external {

        // Comenzar broadcast de transacciones
        vm.startBroadcast();

        // 1. Desplegar el token ERC20
        console.log("Desplegando ERC20Token...");
        ERC20Token token = new ERC20Token();
        console.log("ERC20Token desplegado en:", address(token));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());

        // 2. Desplegar el contrato OrderEscrow
        console.log("\nDesplegando OrderEscrow...");
        OrderEscrow escrow = new OrderEscrow(address(token));
        console.log("OrderEscrow desplegado en:", address(escrow));

        vm.stopBroadcast();

        // Mostrar resumen
        console.log("\n=================================================");
        console.log("RESUMEN DE DESPLIEGUE");
        console.log("=================================================");
        console.log("ERC20Token:", address(token));
        console.log("OrderEscrow:", address(escrow));
        console.log("=================================================");
        console.log("\nGuarda estas direcciones para interactuar con los contratos!");
    }
}
