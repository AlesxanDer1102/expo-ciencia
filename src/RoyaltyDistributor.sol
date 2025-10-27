// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RoyaltyDistributor
 * @notice Contrato para la distribución automática de regalías entre múltiples beneficiarios
 */
contract RoyaltyDistributor is Ownable, ReentrancyGuard {
    /**
     * @dev Constructor that sets the initial owner to the deployer
     */
    constructor() Ownable(msg.sender) {}

    struct Beneficiary {
        address payable wallet;
        uint256 percentage; // En puntos base (10000 = 100%)
    }

    // Mapeo de ID de obra a lista de beneficiarios
    mapping(string => Beneficiary[]) public beneficiaries;
    
    // Eventos
    event BeneficiariesUpdated(string indexed workId, address[] beneficiaries, uint256[] percentages);
    event RoyaltiesDistributed(
        string indexed workId,
        address token,
        uint256 totalAmount,
        address[] recipients,
        uint256[] amounts
    );

    /**
     * @dev Establece o actualiza los beneficiarios para una obra específica
     * @param workId Identificador único de la obra
     * @param _beneficiaries Lista de direcciones de los beneficiarios
     * @param _percentages Porcentajes para cada beneficiario (en puntos base, 10000 = 100%)
     */
    function setBeneficiaries(
        string calldata workId,
        address[] calldata _beneficiaries,
        uint256[] calldata _percentages
    ) external onlyOwner {
        require(_beneficiaries.length == _percentages.length, "Arrays length mismatch");
        
        // Eliminar beneficiarios existentes
        delete beneficiaries[workId];
        
        // Añadir nuevos beneficiarios
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            require(_beneficiaries[i] != address(0), "Invalid address");
            require(_percentages[i] > 0, "Percentage must be greater than 0");
            
            beneficiaries[workId].push(Beneficiary({
                wallet: payable(_beneficiaries[i]),
                percentage: _percentages[i]
            }));
            
            totalPercentage += _percentages[i];
        }
        
        require(totalPercentage <= 10000, "Total percentage exceeds 100%");
        
        emit BeneficiariesUpdated(workId, _beneficiaries, _percentages);
    }

    /**
     * @dev Distribuye los fondos entre los beneficiarios según los porcentajes establecidos
     * @param workId Identificador de la obra
     * @param tokenAddress Dirección del token ERC20 (address(0) para ETH)
     * @param amount Cantidad total a distribuir
     */
    function distributeRoyalties(
        string calldata workId,
        address tokenAddress,
        uint256 amount
    ) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        Beneficiary[] storage workBeneficiaries = beneficiaries[workId];
        require(workBeneficiaries.length > 0, "No beneficiaries set for this work");
        
        uint256 totalAmount = tokenAddress == address(0) ? msg.value : amount;
        require(totalAmount > 0, "No funds to distribute");
        
        if (tokenAddress != address(0)) {
            // Transferir tokens al contrato primero
            IERC20 token = IERC20(tokenAddress);
            require(
                token.transferFrom(msg.sender, address(this), amount),
                "Token transfer failed"
            );
        }
        
        address[] memory recipients = new address[](workBeneficiaries.length);
        uint256[] memory amounts = new uint256[](workBeneficiaries.length);
        
        // Distribuir fondos
        uint256 distributed = 0;
        for (uint256 i = 0; i < workBeneficiaries.length; i++) {
            Beneficiary memory beneficiary = workBeneficiaries[i];
            uint256 share = (totalAmount * beneficiary.percentage) / 10000;
            
            if (i == workBeneficiaries.length - 1) {
                // Asegurar que no queden fondos sin distribuir por redondeos
                share = totalAmount - distributed;
            } else {
                distributed += share;
            }
            
            // Transferir al beneficiario
            if (tokenAddress == address(0)) {
                (bool success, ) = beneficiary.wallet.call{value: share}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenAddress).transfer(beneficiary.wallet, share);
            }
            
            // Guardar para el evento
            recipients[i] = beneficiary.wallet;
            amounts[i] = share;
        }
        
        emit RoyaltiesDistributed(workId, tokenAddress, totalAmount, recipients, amounts);
    }

    /**
     * @dev Permite al propietario retirar tokens atrapados en el contrato
     * @param tokenAddress Dirección del token (address(0) para ETH)
     */
    function withdrawFunds(address tokenAddress) external onlyOwner {
        if (tokenAddress == address(0)) {
            uint256 balance = address(this).balance;
            require(balance > 0, "No ETH balance to withdraw");
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(tokenAddress);
            uint256 balance = token.balanceOf(address(this));
            require(balance > 0, "No token balance to withdraw");
            require(token.transfer(owner(), balance), "Token transfer failed");
        }
    }
    
    // Para recibir ETH
    receive() external payable {}
}