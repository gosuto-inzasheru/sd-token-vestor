# Vester

Vester is a smart contract system designed to manage token vesting for beneficiaries using Stake DAO's SD Token Gauge. It provides a factory pattern for deploying individual vesting contracts and handles rewards distribution through liquidity gauges.

## Key Components

1. **Factory**: A contract that deploys and manages individual vesting contracts for beneficiaries. It uses a clone pattern to minimize deployment costs.

2. **Vester**: The main vesting contract that:
   - Manages vesting positions with customizable vesting periods
   - Handles reward claims from liquidity gauges
   - Supports voting reward claims through Merkle proofs
   - Integrates with Stake DAO's delegation system

## How It Works

1. **Deployment and Setup**:
   - The Factory deploys individual vesting contracts for each beneficiary
   - Each vesting contract is initialized with a beneficiary address
   - Automatic delegation setup to Stake DAO's governance system

2. **Vesting Process**:
   - Managers can deposit tokens with custom or default vesting periods
   - Tokens are locked in the contract until the vesting period ends
   - Beneficiaries can claim tokens once fully vested
   - Rewards from liquidity gauges can be claimed separately

## Roles and Permissions

- **Manager**: Can deposit tokens and update delegation settings
- **Beneficiary**: Can claim vested tokens and rewards
- **Ragequit Role**: Can execute emergency withdrawal
- **Admin**: Can deploy new vesting contracts and update implementation

## Acknowledgements

- [Maxi Pay](https://github.com/BalancerMaxis/maxi-pay) for the initial implementation and guidance.

## License

This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). For more details, see the LICENSE file in the project root.