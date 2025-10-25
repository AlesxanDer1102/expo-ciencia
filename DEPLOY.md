# Guía de Despliegue

Este documento explica cómo desplegar los contratos ERC20Token y OrderEscrow en diferentes redes.

## Prerequisitos

1. **Foundry** instalado ([Guía de instalación](https://book.getfoundry.sh/getting-started/installation))
2. Una **wallet** con fondos para gas
3. **RPC URL** de la red donde quieres desplegar
4. **Private key** de tu wallet

## Configuración Inicial

### 1. Configurar variables de entorno

Copia el archivo `.env.example` a `.env`:

```bash
cp .env.example .env
```

Edita el archivo `.env` y completa:

```bash
# Tu private key (sin el prefijo 0x)
PRIVATE_KEY=tu_private_key_aqui

# RPC URL de la red (ejemplos):
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
POLYGON_RPC_URL=https://polygon-rpc.com
```

⚠️ **IMPORTANTE**: Nunca compartas tu `.env` file. Está en `.gitignore` para tu seguridad.

### 2. Cargar variables de entorno

```bash
source .env
```

## Despliegue

### Opción 1: Red Local (Anvil)

Útil para desarrollo y testing rápido.

**Paso 1**: Inicia Anvil en una terminal:

```bash
anvil
```

**Paso 2**: En otra terminal, despliega los contratos:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast
```

Anvil te dará cuentas de prueba con ETH. Usa la private key de la primera cuenta:
```
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Opción 2: Testnet (Sepolia)

**Paso 1**: Asegúrate de tener SepoliaETH en tu wallet
- Consigue SepoliaETH gratis: https://sepoliafaucet.com/

**Paso 2**: Despliega:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### Opción 3: Mainnet/Polygon

⚠️ **CUIDADO**: Esto usará fondos reales.

```bash
# Polygon Mainnet
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast \
  --verify \
  -vvvv

# Ethereum Mainnet
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Verificar Contratos en Etherscan

Si no usaste `--verify` durante el despliegue, puedes verificar después:

### ERC20Token

```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --watch \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <DIRECCION_DEL_TOKEN> \
  src/ERC20Token.sol:ERC20Token
```

### OrderEscrow

```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address)" <DIRECCION_DEL_TOKEN>) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <DIRECCION_DEL_ESCROW> \
  src/OrderEscrow.sol:OrderEscrow
```

## Después del Despliegue

### 1. Guardar las direcciones

El script mostrará algo como:

```
=================================================
RESUMEN DE DESPLIEGUE
=================================================
ERC20Token: 0x1234567890123456789012345678901234567890
OrderEscrow: 0x0987654321098765432109876543210987654321
=================================================
```

**Guarda estas direcciones** - las necesitarás para tu frontend.

### 2. Verificar en el explorador de bloques

- **Sepolia**: https://sepolia.etherscan.io/address/TU_DIRECCION
- **Polygon**: https://polygonscan.com/address/TU_DIRECCION
- **Mainnet**: https://etherscan.io/address/TU_DIRECCION

### 3. Probar el faucet

Una vez desplegado, puedes obtener tokens de prueba:

```bash
# Usando cast
cast send <DIRECCION_DEL_TOKEN> "faucet()" \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Verificar balance
cast call <DIRECCION_DEL_TOKEN> "balanceOf(address)(uint256)" <TU_WALLET> \
  --rpc-url $SEPOLIA_RPC_URL
```

### 4. Crear una orden de prueba

```bash
# 1. Aprobar tokens al escrow
cast send <DIRECCION_DEL_TOKEN> \
  "approve(address,uint256)" \
  <DIRECCION_DEL_ESCROW> \
  1000000000000000000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# 2. Crear orden (1000 tokens al provider 0x...)
cast send <DIRECCION_DEL_ESCROW> \
  "createOrder(address,uint256)" \
  <DIRECCION_DEL_PROVIDER> \
  1000000000000000000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

## Estructura de Archivos Generados

Después del despliegue, Foundry creará:

```
broadcast/
└── Deploy.s.sol/
    └── <chain-id>/
        └── run-latest.json  # Información del despliegue
```

Este archivo contiene:
- Direcciones de los contratos desplegados
- Hashes de las transacciones
- Gas usado
- Otros detalles técnicos

## Troubleshooting

### Error: "Insufficient funds"

- Asegúrate de tener suficiente ETH/MATIC para gas
- En testnets, usa un faucet para obtener fondos

### Error: "Invalid private key"

- Verifica que tu PRIVATE_KEY no tenga el prefijo `0x`
- Asegúrate de que el archivo `.env` esté cargado (`source .env`)

### Error: "Transaction underpriced"

- La red está congestionada
- Intenta aumentar el gas price:

```bash
forge script ... --with-gas-price 50gwei
```

### El contrato no se verifica automáticamente

- Espera unos minutos y verifica manualmente (comandos arriba)
- Asegúrate de tener tu ETHERSCAN_API_KEY configurado

## Seguridad

✅ **HACER**:
- Usa una wallet separada para despliegues
- Guarda las direcciones de los contratos en un lugar seguro
- Verifica los contratos en el explorador de bloques

❌ **NO HACER**:
- Compartir tu archivo `.env`
- Commitear tu private key al repositorio
- Usar la misma wallet para desarrollo y producción

## Recursos Útiles

- [Foundry Book](https://book.getfoundry.sh/)
- [Sepolia Faucet](https://sepoliafaucet.com/)
- [Alchemy](https://www.alchemy.com/) - RPC provider
- [Etherscan](https://etherscan.io/) - Block explorer
- [Polygonscan](https://polygonscan.com/) - Polygon explorer

## Siguiente Paso

Una vez desplegados los contratos, consulta `USAGE.md` para ver cómo integrarlos con tu frontend.
