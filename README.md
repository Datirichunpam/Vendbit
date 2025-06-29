# Vendbit - Mobile Vendor Payment System

A decentralized point-of-sale payment system built on Stacks that enables mobile vendors to accept STX payments through QR code wallets.

## Overview

Vendbit allows street vendors, food trucks, market stalls, and other mobile businesses to:
- Accept cryptocurrency payments instantly
- Generate QR codes for customer transactions  
- Track sales and manage inventory
- Withdraw earnings securely
- Handle disputes and refunds

## Features

- **Vendor Registration**: Vendors can register with business details and QR codes
- **Payment Processing**: Secure STX transfers with automated fee calculation
- **Balance Management**: Track available and pending funds separately
- **Settlement System**: Vendors confirm transactions before funds become available
- **Refund Support**: Vendors and admins can process refunds for pending payments
- **Dispute Resolution**: Customers can dispute payments with reasons
- **Verification System**: Admin verification for trusted vendors
- **Transaction History**: Complete audit trail of all payments

## Contract Functions

### Public Functions

#### Vendor Management
- `register-vendor(name, description, qr-code)` - Register as a new vendor
- `withdraw-funds(amount)` - Withdraw available balance to vendor wallet
- `update-vendor-status(vendor, new-status)` - Admin function to change vendor status
- `verify-vendor(vendor)` - Admin function to verify trusted vendors

#### Payment Processing
- `create-payment(vendor, amount, description, qr-data)` - Create new payment transaction
- `settle-payment(payment-id)` - Vendor confirms received payment
- `refund-payment(payment-id)` - Process refund for pending payment
- `dispute-payment(payment-id, reason)` - Customer disputes a payment

#### System Administration
- `toggle-contract(enabled)` - Enable/disable contract operations

### Read-Only Functions

- `get-vendor(vendor-id)` - Get vendor information and stats
- `get-payment(payment-id)` - Get payment details and status
- `get-vendor-balance(vendor)` - Get vendor's available and pending balances
- `get-payment-dispute(payment-id)` - Get dispute information
- `get-contract-stats()` - Get overall system statistics
- `get-vendor-qr(vendor-id)` - Get vendor's QR code data
- `calculate-payment-fee(amount)` - Calculate platform fee for amount
- `get-net-payment-amount(amount)` - Calculate net amount after fees

## Usage Instructions

### For Vendors

1. **Register Your Business**
   ```clarity
   (contract-call? .Vendbit register-vendor 
     "Pizza Truck" 
     "Authentic wood-fired pizza on wheels" 
     "QR_PIZZA_TRUCK_001")
   ```

2. **Receive Payments**
   - Share your QR code with customers
   - Customers create payments using your vendor address
   - Confirm received payments to unlock funds

3. **Settle Payments**
   ```clarity
   (contract-call? .Vendbit settle-payment u123)
   ```

4. **Withdraw Funds**
   ```clarity
   (contract-call? .Vendbit withdraw-funds u5000000)
   ```

### For Customers

1. **Make Payment**
   ```clarity
   (contract-call? .Vendbit create-payment 
     'SP1VENDOR123... 
     u2000000 
     "2x Pizza Margherita" 
     "ORDER_001_QR_DATA")
   ```

2. **Dispute Payment**
   ```clarity
   (contract-call? .Vendbit dispute-payment 
     u123 
     "Order never received after 30 minutes")
   ```

## System Parameters

- **Platform Fee**: 0.25% (25 basis points)
- **Minimum Payment**: 1 STX (1,000,000 microSTX)
- **Maximum Payment**: 1,000,000 STX
- **Payment States**: pending → settled/refunded
- **Vendor States**: active, suspended, inactive

## Payment Flow

1. Customer scans vendor QR code
2. Customer creates payment with order details
3. STX is transferred to contract escrow
4. Vendor provides goods/services
5. Vendor settles payment to release funds
6. Vendor can withdraw accumulated balance

## Error Codes

- `u100` - Unauthorized operation
- `u101` - Vendor not found
- `u102` - Vendor already exists  
- `u103` - Insufficient funds
- `u104` - Invalid payment parameters
- `u105` - Payment not found
- `u106` - Payment already settled
- `u107` - Invalid refund request
- `u108` - Vendor suspended

## Security Features

- Contract owner controls for emergency situations
- Vendor verification system for trust indicators
- Escrow system holds funds until settlement
- Dispute mechanism for customer protection
- Balance separation (available vs pending)

## Development

### Requirements
- Clarinet 2.0+
- Stacks blockchain testnet/mainnet

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy --testnet
```

## Contract Address

Deploy this contract to your chosen Stacks network and update applications with the contract address.

## License

MIT License - See LICENSE file for details.
