// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ERC20Token - Token para pruebas con función faucet
/// @notice Token ERC20 simple con función faucet para facilitar testing
contract ERC20Token is ERC20 {
    // Constantes
    uint256 public constant FAUCET_AMOUNT = 1000 * 10**18; // 1000 tokens

    // Eventos
    event FaucetUsed(address indexed recipient, uint256 amount);

    constructor() ERC20("Stablecoin Dolar", "USDC") {
        // Mint inicial para el deployer (para facilitar testing)
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    /// @notice Función faucet para obtener tokens de prueba
    /// @dev Cualquiera puede solicitar tokens en cualquier momento
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetUsed(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Función faucet para enviar tokens a otra dirección
    /// @dev Cualquiera puede enviar tokens a cualquier dirección
    /// @param to Dirección que recibirá los tokens
    function faucet(address to) external {
        require(to != address(0), "Invalid address");
        _mint(to, FAUCET_AMOUNT);
        emit FaucetUsed(to, FAUCET_AMOUNT);
    }
}
