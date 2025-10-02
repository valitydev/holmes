#!/usr/bin/env python3
"""
Script to create invoices and register payments for recurrent payment registration.

This script follows the recipe for registering payments that will be used as parent
payments for recurrent payments. It reads data from a CSV file and performs:
1. Create Invoice
2. Register Payment with recurrent token

Usage (run from project root):
    ./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv [options]

Required CSV columns:
- invoice_id: Unique invoice ID
- party_id: Party ID
- shop_id: Shop ID
- product: Product description
- amount: Payment amount (integer, in minor currency units)
- currency: Currency code (e.g., RUB)
- provider_id: Provider ID for routing
- terminal_id: Terminal ID for routing
- provider_transaction_id: Transaction ID from provider
- recurrent_token: Recurrent token for future payments
- card_token: Bank card token
- card_bin: First 6 digits of card number
- card_last_digits: Last 4 digits of card number
- card_payment_system: Payment system (e.g., visa, mastercard)
- cardholder_name: Name on the card
- card_exp_month: Expiration month (1-12)
- card_exp_year: Expiration year (e.g., 2025)

Optional CSV columns:
- context_type: Context type (default: "empty")
- context_data: Context data in base64 (default: empty)
- contact_email: Payer email
- contact_phone: Payer phone number
"""

import os
import sys
import csv
import json
import subprocess
import argparse
import datetime
from typing import Dict, Any, Optional


def parse_args():
    parser = argparse.ArgumentParser(
        description='Create invoices and register payments from CSV',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('csv_file', type=str, help='Path to CSV file with payment data')
    parser.add_argument('--hellgate-host', type=str, default=None,
                       help='Hellgate host (default: from HELLGATE env or "hellgate")')
    parser.add_argument('--hellgate-port', type=int, default=8022,
                       help='Hellgate port (default: 8022)')
    parser.add_argument('--damsel-proto', type=str, default=None,
                       help='Path to damsel proto directory')
    parser.add_argument('--dry-run', action='store_true',
                       help='Print requests without executing them')
    parser.add_argument('--skip-invoice-creation', action='store_true',
                       help='Skip invoice creation, only register payments')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    return parser.parse_args()


def log_info(msg: str, verbose: bool = True):
    """Log info message"""
    if verbose:
        timestamp = datetime.datetime.now().isoformat(timespec='milliseconds')
        print(f"[INFO] {timestamp} {msg}")


def log_error(msg: str):
    """Log error message"""
    timestamp = datetime.datetime.now().isoformat(timespec='milliseconds')
    print(f"[ERROR] {timestamp} {msg}", file=sys.stderr)


def get_woorl_cmd():
    """Get woorl command from woorlrc or use default"""
    try:
        result = subprocess.run(
            'test -f ./woorlrc && source ./woorlrc ; echo ${WOORL[@]:-woorl}',
            shell=True,
            capture_output=True,
            text=True
        )
        cmd = result.stdout.strip().split()
        # If empty or only whitespace, return default
        if not cmd or not cmd[0]:
            return ['woorl']
        return cmd
    except Exception:
        return ['woorl']


def woorl_call(service_url: str, proto_path: str, service: str, func: str, 
               *args, dry_run: bool = False, verbose: bool = False) -> Optional[str]:
    """Call woorl with the given parameters"""
    woorl_cmd = get_woorl_cmd()
    cmd = woorl_cmd + ['--deadline=30s', '-s', proto_path, service_url, service, func]
    
    # Add arguments, converting dicts to JSON
    for arg in args:
        if isinstance(arg, (dict, list)):
            cmd.append(json.dumps(arg))
        else:
            cmd.append(arg)
    
    if verbose or dry_run:
        log_info(f"Command: {' '.join(cmd)}", True)
    
    if dry_run:
        return None
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            log_error(f"Command failed with code {result.returncode}")
            log_error(f"stdout: {result.stdout}")
            log_error(f"stderr: {result.stderr}")
            return None
        return result.stdout
    except subprocess.TimeoutExpired:
        log_error("Command timed out")
        return None
    except Exception as e:
        log_error(f"Command failed: {e}")
        return None


def create_invoice(row: Dict[str, str], service_url: str, proto_path: str,
                   dry_run: bool = False, verbose: bool = False) -> bool:
    """Create an invoice"""
    log_info(f"Creating invoice {row['invoice_id']}", verbose)
    
    # Build InvoiceParams
    params = {
        "party_id": {"id": row['party_id']},
        "shop_id": {"id": row['shop_id']},
        "details": {
            "product": row['product']
        },
        "due": row.get('due', "2030-12-31T23:59:59Z"),
        "cost": {
            "amount": int(row['amount']),
            "currency": {"symbolic_code": row['currency']}
        },
        "context": {
            "type": row.get('context_type', "empty"),
            "data": row.get('context_data', "")
        },
        "id": row['invoice_id']
    }
    
    # Add optional external_id if present
    if 'external_id' in row and row['external_id']:
        params['external_id'] = row['external_id']
    
    result = woorl_call(
        service_url, proto_path, 'Invoicing', 'Create',
        params, dry_run=dry_run, verbose=verbose
    )
    
    if result is None and not dry_run:
        log_error(f"Failed to create invoice {row['invoice_id']}")
        return False
    
    log_info(f"Invoice {row['invoice_id']} created successfully", verbose)
    return True


def register_payment(row: Dict[str, str], service_url: str, proto_path: str,
                    dry_run: bool = False, verbose: bool = False) -> bool:
    """Register a payment for the invoice"""
    log_info(f"Registering payment for invoice {row['invoice_id']}", verbose)
    
    # Build BankCard
    bank_card = {
        "token": row['card_token'],
        "bin": row['card_bin'],
        "last_digits": row['card_last_digits']
    }
    
    # Add optional card fields
    if 'card_payment_system' in row and row['card_payment_system']:
        bank_card['payment_system'] = {"id": row['card_payment_system']}
    
    if 'cardholder_name' in row and row['cardholder_name']:
        bank_card['cardholder_name'] = row['cardholder_name']
    
    if 'card_exp_month' in row and 'card_exp_year' in row and row['card_exp_month'] and row['card_exp_year']:
        bank_card['exp_date'] = {
            "month": int(row['card_exp_month']),
            "year": int(row['card_exp_year'])
        }
    
    # Build ContactInfo
    contact_info = {}
    if 'contact_email' in row and row['contact_email']:
        contact_info['email'] = row['contact_email']
    if 'contact_phone' in row and row['contact_phone']:
        contact_info['phone_number'] = row['contact_phone']
    
    # Build RegisterInvoicePaymentParams
    params = {
        "payer_params": {
            "payment_resource": {
                "resource": {
                    "payment_tool": {
                        "bank_card": bank_card
                    }
                },
                "contact_info": contact_info
            }
        },
        "route": {
            "provider": {"id": int(row['provider_id'])},
            "terminal": {"id": int(row['terminal_id'])}
        },
        "transaction_info": {
            "id": row['provider_transaction_id'],
            "extra": {}
        }
    }
    
    # Add recurrent_token
    if 'recurrent_token' in row and row['recurrent_token']:
        params['recurrent_token'] = row['recurrent_token']
    
    # Add optional payment_id if specified
    if 'payment_id' in row and row['payment_id']:
        params['id'] = row['payment_id']
    
    result = woorl_call(
        service_url, proto_path, 'Invoicing', 'RegisterPayment',
        json.dumps(row['invoice_id']), params, dry_run=dry_run, verbose=verbose
    )
    
    if result is None and not dry_run:
        log_error(f"Failed to register payment for invoice {row['invoice_id']}")
        return False
    
    log_info(f"Payment registered successfully for invoice {row['invoice_id']}", verbose)
    return True


def validate_row(row: Dict[str, str], row_num: int, skip_invoice: bool = False) -> bool:
    """Validate that a row has all required fields"""
    required_fields = [
        'invoice_id', 'amount', 'currency',
        'provider_id', 'terminal_id', 'provider_transaction_id',
        'card_token', 'card_bin', 'card_last_digits'
    ]
    
    if not skip_invoice:
        required_fields.extend(['party_id', 'shop_id', 'product'])
    
    missing_fields = [field for field in required_fields if not row.get(field)]
    
    if missing_fields:
        log_error(f"Row {row_num}: Missing required fields: {', '.join(missing_fields)}")
        return False
    
    return True


def process_csv(csv_file: str, args):
    """Process CSV file and create invoices/register payments"""
    # Determine paths
    if args.damsel_proto:
        proto_path = args.damsel_proto
    else:
        # Try to find damsel from current working directory (scripts run from project root)
        # or from script directory (for backwards compatibility)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        cwd_proto = os.path.join(os.getcwd(), 'damsel', 'proto', 'payment_processing.thrift')
        script_proto = os.path.join(script_dir, '..', '..', '..', 'damsel', 'proto', 'payment_processing.thrift')
        
        if os.path.exists(cwd_proto):
            proto_path = cwd_proto
        elif os.path.exists(script_proto):
            proto_path = script_proto
        else:
            # Last resort: use relative path from cwd
            proto_path = 'damsel/proto/payment_processing.thrift'
    
    # Build service URL
    hellgate_host = args.hellgate_host or os.environ.get('HELLGATE', 'hellgate')
    service_url = f"http://{hellgate_host}:{args.hellgate_port}/v1/processing/invoicing"
    
    log_info(f"Service URL: {service_url}", args.verbose)
    log_info(f"Proto path: {proto_path}", args.verbose)
    
    # Read and process CSV
    success_count = 0
    error_count = 0
    
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        # Validate headers
        if not reader.fieldnames:
            log_error("CSV file is empty or has no headers")
            return 1
        
        log_info(f"CSV columns: {', '.join(reader.fieldnames)}", args.verbose)
        
        for row_num, row in enumerate(reader, start=2):  # Start at 2 (1 is header)
            if not validate_row(row, row_num, args.skip_invoice_creation):
                error_count += 1
                continue
            
            try:
                # Create invoice (unless skipped)
                if not args.skip_invoice_creation:
                    if not create_invoice(row, service_url, proto_path, args.dry_run, args.verbose):
                        error_count += 1
                        continue
                
                # Register payment
                if not register_payment(row, service_url, proto_path, args.dry_run, args.verbose):
                    error_count += 1
                    continue
                
                success_count += 1
                
            except Exception as e:
                log_error(f"Row {row_num}: Unexpected error: {e}")
                error_count += 1
                if args.verbose:
                    import traceback
                    traceback.print_exc()
    
    # Summary
    print("\n" + "="*60)
    print(f"Processing complete:")
    print(f"  Successful: {success_count}")
    print(f"  Failed: {error_count}")
    print("="*60)
    
    return 0 if error_count == 0 else 1


def main():
    args = parse_args()
    
    # Check if CSV file exists
    if not os.path.exists(args.csv_file):
        log_error(f"CSV file not found: {args.csv_file}")
        return 1
    
    return process_csv(args.csv_file, args)


if __name__ == '__main__':
    sys.exit(main())


