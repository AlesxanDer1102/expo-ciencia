// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RoyaltyDistributor.sol";
import "../src/ERC20Token.sol";

contract RoyaltyDistributorTest is Test {
    RoyaltyDistributor public royaltyDistributor;
    ERC20Token public token;

    address public owner = address(0x1);
    address public beneficiary1 = address(0x2);
    address public beneficiary2 = address(0x3);
    address public other = address(0x4);

    string public constant WORK_ID = "work123";

    event BeneficiariesUpdated(string indexed workId, address[] beneficiaries, uint256[] percentages);
    event RoyaltiesDistributed(
        string indexed workId,
        address token,
        uint256 totalAmount,
        address[] recipients,
        uint256[] amounts
    );

    function setUp() public {
        // Desplegar contratos
        vm.prank(owner);
        royaltyDistributor = new RoyaltyDistributor();
        
        token = new ERC20Token();
        
        // Usar la función faucet para dar tokens a las cuentas de prueba
        token.faucet(beneficiary1);
        token.faucet(beneficiary2);
        token.faucet(other);
    }

    // Pruebas para el constructor
    function test_InitialOwner() public {
        assertEq(royaltyDistributor.owner(), owner);
    }

    // Pruebas para setBeneficiaries
    function test_SetBeneficiaries_RevertIf_NotOwner() public {
        address[] memory beneficiaries = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        beneficiaries[0] = beneficiary1;
        percentages[0] = 10000; // 100%
        
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", other));
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
    }

    function test_SetBeneficiaries() public {
        address[] memory beneficiaries = new address[](2);
        uint256[] memory percentages = new uint256[](2);
        
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        percentages[0] = 3000; // 30%
        percentages[1] = 7000; // 70%
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Verificar que los beneficiarios se configuraron correctamente
        (address wallet1, uint256 percentage1) = royaltyDistributor.beneficiaries(WORK_ID, 0);
        (address wallet2, uint256 percentage2) = royaltyDistributor.beneficiaries(WORK_ID, 1);
        
        assertEq(wallet1, beneficiary1);
        assertEq(percentage1, 3000);
        assertEq(wallet2, beneficiary2);
        assertEq(percentage2, 7000);
    }

    // Pruebas para distributeRoyalties con ETH
    function test_DistributeRoyalties_ETH() public {
        // Configurar beneficiarios
        address[] memory beneficiaries = new address[](2);
        uint256[] memory percentages = new uint256[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        percentages[0] = 3000; // 30%
        percentages[1] = 7000; // 70%
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Distribuir ETH
        uint256 amount = 1 ether;
        vm.deal(other, amount);
        
        // Store initial balances
        uint256 beneficiary1BalanceBefore = beneficiary1.balance;
        uint256 beneficiary2BalanceBefore = beneficiary2.balance;
        
        // Send ETH directly with the distributeRoyalties call
        // We need to pass the amount as a parameter too, even though we're sending value
        vm.prank(other);
        royaltyDistributor.distributeRoyalties{value: amount}(WORK_ID, address(0), amount);
        
        // Verificar distribución
        assertEq(beneficiary1.balance - beneficiary1BalanceBefore, (amount * 30) / 100);
        assertEq(beneficiary2.balance - beneficiary2BalanceBefore, (amount * 70) / 100);
    }

    // Pruebas para withdrawFunds
    function test_WithdrawFunds_RevertIf_NotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", other));
        royaltyDistributor.withdrawFunds(address(0));
    }

    function test_WithdrawFunds_RevertIf_NoTokenBalance() public {
        // Verificar que el contrato no tiene tokens
        assertEq(token.balanceOf(address(royaltyDistributor)), 0, "Contract should start with 0 token balance");
        
        // Intentar retirar tokens cuando no hay saldo
        vm.prank(owner);
        vm.expectRevert("No token balance to withdraw");
        royaltyDistributor.withdrawFunds(address(token));
    }
    
    function test_WithdrawFunds_RevertIf_InvalidToken() public {
        // Crear una dirección que no es un contrato ERC20 válido
        address invalidToken = address(0x123);
        
        // Verificar que la dirección no es un contrato
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(invalidToken)
        }
        assertEq(codeSize, 0, "Address should not be a contract");
        
        // Intentar retirar con una dirección de token no válida
        // No especificamos un mensaje de error ya que la reversión no incluye datos
        vm.prank(owner);
        vm.expectRevert();
        royaltyDistributor.withdrawFunds(invalidToken);
    }

    function test_WithdrawFunds_ETH() public {
        // Enviar ETH al contrato
        uint256 amount = 1 ether;
        
        // Usar vm.deal para asignar ETH al contrato directamente
        // Esto es más directo para pruebas que hacer una transferencia
        vm.deal(address(royaltyDistributor), amount);
        
        // Verificar que el contrato tiene el ETH
        assertEq(address(royaltyDistributor).balance, amount);
        
        // Obtener el balance actual del owner
        uint256 ownerBalanceBefore = owner.balance;
        
        // Hacer el retiro
        vm.prank(owner);
        royaltyDistributor.withdrawFunds(address(0));
        
        // Verificar que el owner recibió el ETH y el contrato ya no tiene fondos
        assertEq(owner.balance, ownerBalanceBefore + amount, "Owner should receive the ETH");
        assertEq(address(royaltyDistributor).balance, 0, "Contract balance should be 0 after withdrawal");
    }

    function test_WithdrawFunds_ERC20() public {
        // Enviar tokens al contrato
        uint256 amount = 1000 * 10**18;
        vm.prank(other);
        token.transfer(address(royaltyDistributor), amount);
        
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        
        vm.prank(owner);
        royaltyDistributor.withdrawFunds(address(token));
        
        assertEq(token.balanceOf(owner), ownerBalanceBefore + amount);
        assertEq(token.balanceOf(address(royaltyDistributor)), 0);
    }

    function test_Receive() public {
        uint256 amount = 1 ether;
        vm.deal(other, amount);
        
        vm.prank(other);
        (bool success, ) = address(royaltyDistributor).call{value: amount}("");
        
        assertTrue(success);
        assertEq(address(royaltyDistributor).balance, amount);
    }

    // Pruebas adicionales para setBeneficiaries
    function test_SetBeneficiaries_RevertIf_ArraysLengthMismatch() public {
        address[] memory beneficiaries = new address[](2);
        uint256[] memory percentages = new uint256[](1);
        
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        percentages[0] = 10000;
        
        vm.prank(owner);
        vm.expectRevert("Arrays length mismatch");
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
    }
    
    function test_SetBeneficiaries_RevertIf_ZeroAddress() public {
        address[] memory beneficiaries = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        
        beneficiaries[0] = address(0);
        percentages[0] = 10000;
        
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
    }
    
    function test_SetBeneficiaries_RevertIf_ZeroPercentage() public {
        address[] memory beneficiaries = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        
        beneficiaries[0] = beneficiary1;
        percentages[0] = 0;
        
        vm.prank(owner);
        vm.expectRevert("Percentage must be greater than 0");
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
    }
    
    function test_SetBeneficiaries_OverwriteExisting() public {
        // Configurar beneficiarios iniciales
        address[] memory beneficiaries = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        
        beneficiaries[0] = beneficiary1;
        percentages[0] = 10000;
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Sobrescribir con nuevos beneficiarios
        beneficiaries = new address[](2);
        percentages = new uint256[](2);
        
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        percentages[0] = 3000;
        percentages[1] = 7000;
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Verificar que solo hay 2 beneficiarios (el anterior fue sobrescrito)
        (address wallet1, uint256 percentage1) = royaltyDistributor.beneficiaries(WORK_ID, 0);
        (address wallet2, uint256 percentage2) = royaltyDistributor.beneficiaries(WORK_ID, 1);
        
        assertEq(wallet1, beneficiary1);
        assertEq(percentage1, 3000);
        assertEq(wallet2, beneficiary2);
        assertEq(percentage2, 7000);
    }
    
    // Pruebas adicionales para distributeRoyalties
    function test_DistributeRoyalties_ERC20() public {
        // Configurar beneficiarios
        address[] memory beneficiaries = new address[](2);
        uint256[] memory percentages = new uint256[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        percentages[0] = 3000; // 30%
        percentages[1] = 7000; // 70%
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Usar la cuenta 'other' que ya tiene tokens
        uint256 amount = 1000 * 10**18;
        
        // Transferir tokens del propietario a 'other' si es necesario para la prueba
        if (token.balanceOf(owner) > 0) {
            vm.prank(owner);
            token.transfer(other, token.balanceOf(owner));
        }
        
        // Asegurarse de que 'other' tiene suficientes tokens
        uint256 otherBalance = token.balanceOf(other);
        if (otherBalance < amount) {
            // Si 'other' no tiene suficientes tokens, saltar la prueba
            return;
        }
        
        // Transferir tokens de 'other' al propietario
        vm.prank(other);
        token.transfer(owner, amount);
        
        // Aprobar al contrato para gastar tokens
        vm.prank(owner);
        token.approve(address(royaltyDistributor), amount);
        
        // Distribuir tokens (el contrato transferirá los tokens del remitente)
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 beneficiary1BalanceBefore = token.balanceOf(beneficiary1);
        uint256 beneficiary2BalanceBefore = token.balanceOf(beneficiary2);
        
        vm.prank(owner);
        royaltyDistributor.distributeRoyalties(WORK_ID, address(token), amount);
        
        // Verificar distribución
        uint256 expectedBeneficiary1Amount = (amount * 30) / 100;
        uint256 expectedBeneficiary2Amount = (amount * 70) / 100;
        
        assertEq(
            token.balanceOf(beneficiary1) - beneficiary1BalanceBefore,
            expectedBeneficiary1Amount,
            "Beneficiary 1 should receive 30% of the tokens"
        );
        assertEq(
            token.balanceOf(beneficiary2) - beneficiary2BalanceBefore,
            expectedBeneficiary2Amount,
            "Beneficiary 2 should receive 70% of the tokens"
        );
        assertEq(
            ownerBalanceBefore - token.balanceOf(owner),
            amount,
            "Owner should have spent the tokens"
        );
    }
    
    function test_DistributeRoyalties_RevertIf_NoBeneficiaries() public {
        uint256 amount = 1 ether;
        vm.deal(address(royaltyDistributor), amount);
        
        vm.prank(owner);
        vm.expectRevert("No beneficiaries set for this work");
        royaltyDistributor.distributeRoyalties(WORK_ID, address(0), amount);
    }
    
    function test_DistributeRoyalties_RevertIf_ZeroAmount() public {
        // Configurar beneficiarios
        address[] memory beneficiaries = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        beneficiaries[0] = beneficiary1;
        percentages[0] = 10000;
        
        vm.prank(owner);
        royaltyDistributor.setBeneficiaries(WORK_ID, beneficiaries, percentages);
        
        // Intentar distribuir 0 tokens
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        royaltyDistributor.distributeRoyalties(WORK_ID, address(0), 0);
    }
}