// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CashbackRewards
 * @dev Contrato para gestionar un sistema de recompensas con cashback
 * Permite a los comerciantes ofrecer cashback a sus clientes en forma de puntos
 * que pueden ser canjeados por descuentos o beneficios futuros.
 */
contract CashbackRewards is Ownable, ReentrancyGuard {
    // Referencia al contrato del token ERC20
    IERC20 public paymentToken;

    // Estructura para almacenar la configuración de recompensas
    struct RewardConfig {
        bool isActive;          // Si las recompensas están activas
        uint256 cashbackRate;   // Tasa de cashback en puntos base (100 = 1%)
        uint256 pointsRate;     // Puntos por cada token gastado (ej: 100 = 1 punto por token)
        uint256 minPurchase;    // Compra mínima en tokens para obtener cashback
    }

    // Configuración de recompensas actual
    RewardConfig public rewardConfig;
    
    // Mapeo de direcciones a sus puntos acumulados
    // 1 punto = 0.01 tokens (ajustable según pointsRate)
    mapping(address => uint256) public userPoints;
    
    // Eventos
    event CashbackEarned(
        address indexed user, 
        address indexed token, 
        uint256 amount, 
        uint256 pointsEarned
    );
    
    event PointsRedeemed(
        address indexed user, 
        uint256 points, 
        address token, 
        uint256 amount
    );
    
    event RewardConfigUpdated(
        address indexed user, 
        bool isActive, 
        uint256 cashbackRate, 
        uint256 pointsRate, 
        uint256 minPurchase
    );

    /**
     * @dev Constructor que establece el token de pago y el propietario
     * @param _tokenAddress Dirección del contrato del token ERC20
     */
    constructor(address _tokenAddress) Ownable(msg.sender) {
        require(_tokenAddress != address(0), "Invalid token address");
        paymentToken = IERC20(_tokenAddress);
        
        // Configuración inicial por defecto
        // 5% de cashback, 100 puntos por token, mínimo 10 tokens
        rewardConfig = RewardConfig({
            isActive: true,
            cashbackRate: 500,  // 5%
            pointsRate: 100,    // 1 token = 100 puntos (1 punto = 0.01 tokens)
            minPurchase: 10 * 10**18  // 10 tokens (asumiendo 18 decimales)
        });
    }

    /**
     * @notice Actualiza la configuración de recompensas
     * @param isActive Si las recompensas están activas
     * @param cashbackRate Tasa de cashback en puntos base (100 = 1%)
     * @param pointsRate Puntos por cada token gastado (ej: 100 = 1 punto por token)
     * @param minPurchase Compra mínima en tokens para obtener cashback
     */
    function setRewardConfig(
        bool isActive,
        uint256 cashbackRate,
        uint256 pointsRate,
        uint256 minPurchase
    ) external onlyOwner {
        require(cashbackRate <= 1000, "Cashback rate cannot exceed 10%");
        require(pointsRate > 0, "Points rate must be greater than 0");
        
        rewardConfig = RewardConfig({
            isActive: isActive,
            cashbackRate: cashbackRate,
            pointsRate: pointsRate,
            minPurchase: minPurchase
        });
        
        emit RewardConfigUpdated(msg.sender, isActive, cashbackRate, pointsRate, minPurchase);
    }

    /**
     * @notice Procesa un pago con cashback en tokens
     * @dev El comprador debe aprobar previamente los tokens
     * @param amount Monto total del pago en tokens
     * @param recipient Dirección del vendedor que recibirá el pago
     */
    function processPayment(
        uint256 amount,
        address recipient
    ) external nonReentrant {
        require(rewardConfig.isActive, "Rewards program is not active");
        require(amount >= rewardConfig.minPurchase, "Purchase amount below minimum");
        require(recipient != address(0), "Invalid recipient address");
        
        // Transferir tokens del comprador al contrato
        bool success = paymentToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        // Calcular cashback (en tokens)
        uint256 cashbackAmount = (amount * rewardConfig.cashbackRate) / 10000;
        uint256 recipientAmount = amount - cashbackAmount;
        
        // Transferir al vendedor (monto total - cashback)
        success = paymentToken.transfer(recipient, recipientAmount);
        require(success, "Failed to transfer tokens to recipient");
        
        // Calcular puntos ganados (1 token = rewardConfig.pointsRate puntos)
        uint256 pointsEarned = (amount * rewardConfig.pointsRate) / 10**18;
        userPoints[msg.sender] += pointsEarned;
        
        emit CashbackEarned(msg.sender, address(paymentToken), cashbackAmount, pointsEarned);
    }

    /**
     * @notice Canjear puntos por tokens
     * @param points Cantidad de puntos a canjear
     */
    function redeemPoints(uint256 points) external nonReentrant {
        require(points > 0, "Cannot redeem 0 points");
        require(userPoints[msg.sender] >= points, "Insufficient points");
        
        // Calcular la cantidad de tokens a canjear
        // points / pointsRate * 10^18 para manejar decimales
        uint256 tokenAmount = (points * 10**18) / rewardConfig.pointsRate;
        
        // Verificar que el contrato tenga suficientes tokens
        uint256 contractBalance = paymentToken.balanceOf(address(this));
        require(contractBalance >= tokenAmount, "Insufficient contract balance");
        
        // Actualizar el saldo de puntos
        userPoints[msg.sender] -= points;
        
        // Transferir los tokens al usuario
        bool success = paymentToken.transfer(msg.sender, tokenAmount);
        require(success, "Token transfer failed");
        
        emit PointsRedeemed(msg.sender, points, address(paymentToken), tokenAmount);
    }

    /**
     * @notice Permite al propietario retirar tokens atrapados
     * @param amount Cantidad de tokens a retirar
     */
    function withdrawFunds(uint256 amount) external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        require(amount <= balance, "Insufficient balance");
        
        bool success = paymentToken.transfer(owner(), amount);
        require(success, "Token transfer failed");
    }

    // Función para recibir ETH
    receive() external payable {}
}