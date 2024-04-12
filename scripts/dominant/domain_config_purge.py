#! /usr/bin/env python3

import subprocess
import sys
import json
import copy
import os

import domain_config_tools as dctools
import common_tools as ctools

def make_remove_op(obj):
    return {
        "ops": [
                {
                    "remove": {
                        "object": obj
                }
            }
        ]
    }

def domain_config_purge(ip_addr_port, attempts):

    all_time_removed_cnt = 0

    for cnt in range(attempts):
        print(f'Purge domain config ==================> attempt #{cnt}..')

        # Get domain config
        print("Checkout domain config, it may take some time..")
        raw_data = ctools.service_call(
            'domain_config_repository',
            ip_addr_port,
            'Checkout',
            dctools.domain_make_version('head')
        )
        data = json.loads(raw_data)
        domain_version = data['version']
        print(f'Domain config of version #{domain_version} received..')
        domain = data['domain']

        all_objects = [obj['value'] for obj in domain]

        objects_amount = len(all_objects)
        if objects_amount == 0:
            print('No objects in config, nothing to do here..')
            print('Done.')
            return

        print(f'{objects_amount} objects found in domain config..')
        print(f'Start purging..')

        success_cnt = 0
        fail_flag = False
        success_flag = False
        for obj  in domain:

            val = obj['value']
            commit = json.dumps(make_remove_op(val))
            call_result = ctools.service_call_safe(
                'domain_config_repository',
                ip_addr_port,
                'Commit',
                str(domain_version),
                commit
            )
            if call_result == 'failed':
                repeate = True
                obj_tag = list(obj['value'].keys())[0]
                obj_ref = obj['value'][obj_tag]['ref']
                print(f'Remove FAILED for DomainObject={obj_tag} Ref={obj_ref}')
                fail_flag = True
            else:
                success_flag = True
                domain_version += 1
                success_cnt += 1
                all_time_removed_cnt += 1
                print(f'Remove SUCCESS for DomainObject={obj_tag} Ref={obj_ref}')

        if fail_flag == False:
            print(f'Removed {all_time_removed_cnt} objects')
            print('All objects removed, purge ok')
            print('Done.')
            return

        if success_flag == False:
            raise Exception(f'No objects removed for the attempt!')

    print(f'Removed {all_time_removed_cnt} objects')
    print(f'Domain config purge hasn\'t been finished completely in {attempts} attempts!')
    print('Done.')

def main():
    parser = ctools.args_init()
    ctools.args_add(parser, '-a', '--ip_addr', help='Dominant IP address')
    ctools.args_add(parser, '-p', '--port', help='Dominant port')
    ctools.args_add(parser, 'attempts', help='Purge attempts amount')
    args = ctools.args_parse(parser)

    domain_config_purge((args.ip_addr, args.port), int(args.attempts))

if __name__ == "__main__":
   main()





