#! /usr/bin/env python3

import os
import sys
import json
import subprocess
import argparse
import datetime

env_default_service_ipaddr = 'FISTFUL_IPADDR'
env_default_service_port = 'FISTFUL_PORT'

default_service_host = 'fistful_server'
default_service_port = 8022

def args_init():
    return argparse.ArgumentParser()


def args_add(parser, *args, **kwargs):
    parser.add_argument(*args, **kwargs)


def args_parse(parser):
    args = parser.parse_args()
    #print(f'Input params: {args}')
    return args


def service_call(service_name, ip_addr_port, func, *args):
    (service, service_path, service_proto_path) = service_get(service_name)
    service_url = service_resolve_url(service_path, *ip_addr_port)
    time = datetime.datetime.now().isoformat(timespec='milliseconds')
    #print(f'{time} Calling {service_name} {func}..')
    return woorl_call(service_url, service_proto_path, service, func, *args)

def service_call_safe(service_name, ip_addr_port, func, *args):
    (service, service_path, service_proto_path) = service_get(service_name)
    service_url = service_resolve_url(service_path, *ip_addr_port)
    time = datetime.datetime.now().isoformat(timespec='milliseconds')
    #print(f'{time} Calling {service_name} {func}..')
    return woorl_call_safe(service_url, service_proto_path, service, func, *args)


def service_resolve_url(service_path, ip_addr, port):
    service_addr = (
        ip_addr
        or os.environ.get(env_default_service_ipaddr)
        or default_service_host)
    service_port = (
        port
        or os.environ.get(env_default_service_port)
        or default_service_port)
    service_url = f'http://{ip_addr}:{port}{service_path}'
    #print(f'Service URL resolved: {service_url}')
    return service_url


def service_get(service):
    return {
        'domain_config_repository': (
            ('Repository',
            '/v1/domain/repository',
            '../../damsel/proto/domain_config.thrift')
        ),
        'withdrawal_management': (
            ('Management',
            '/v1/withdrawal',
            'fistful-proto/proto/withdrawal.thrift')
        ),
        'withdrawal_repairer': (
            ('Repairer',
            '/v1/repair/withdrawal',
            'fistful-proto/proto/withdrawal.thrift')
        ),
        'withdrawal_session_management': (
            ('Management',
            '/v1/withdrawal_session',
            'fistful-proto/proto/withdrawal_session.thrift')
        ),
        'shumpune_accounter': (
            ('Accounter',
            '/shumpune',
            'shumaich-proto/proto/shumpune.thrift')
        )
    }[service]


def woorl_call(service_url, proto_path, service, func, *args):
    woorl_cmd = [
        "woorl", "--deadline=30s", "-s", proto_path, service_url,
        service, func
    ] + [maybe_json_dumps(arg) for arg in args]
    try:
        #print(f'Calling woorl with cmd={woorl_cmd}')
        return subprocess.check_output(woorl_cmd, text=True, stderr=subprocess.STDOUT, timeout=None)
    except subprocess.CalledProcessError as e:
        #print(e.output, file=sys.stderr)
        exit(e.returncode)

def woorl_call_safe(service_url, proto_path, service, func, *args):
    woorl_cmd = [
        "woorl", "--deadline=30s", "-s", proto_path, service_url,
        service, func
    ] + [maybe_json_dumps(arg) for arg in args]
    try:
        #print(f'Calling woorl with cmd={woorl_cmd}')
        return subprocess.check_output(woorl_cmd, text=True, stderr=subprocess.STDOUT, timeout=None)
    except subprocess.CalledProcessError as e:
        return 'failed'

def maybe_json_dumps(woorl_arg):
    if isinstance(woorl_arg, dict):
        return json.dumps(woorl_arg)
    return woorl_arg


def file_open(filename, mode):
    date = datetime.datetime.now().isoformat(timespec='seconds')
    filename += f'_{date}.json'
    filename = filename_clean(filename)
    return open(filename, mode)


def filename_clean(filename):
    for char in '<>"/\|?* ':
        filename = filename.replace(char, '')
    return filename
