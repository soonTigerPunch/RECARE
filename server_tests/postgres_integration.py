#!/usr/bin/env python3
"""Real SQL checks against an already running disposable PostgreSQL Docker container.

No ports, credentials, cloud project or OpenAI access are needed. This script
creates and drops its own database; it never starts or stops the container.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--container', required=True, help='Disposable local PostgreSQL container')
args = parser.parse_args()
db = 'recare_test_' + uuid.uuid4().hex
environment = os.environ.copy()
for name in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
    environment.pop(name, None)


def sql(statement, database=db):
    result = subprocess.run(
        ['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', args.container,
         'psql', '-X', '-qAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1'],
        input=statement, text=True, capture_output=True, env=environment, check=True,
    )
    return result.stdout.strip()


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def reset(daily=10_000_000, monthly=100_000_000, concurrent=100):
    sql('truncate recipe_private.jobs,recipe_private.quotas,recipe_private.budgets,recipe_private.rate_windows;'
        f'update recipe_private.config set enabled=true, daily_budget_micro={daily},'
        f'monthly_budget_micro={monthly},request_reserve_micro=70000,max_concurrent={concurrent};')


def issue(session, request_id):
    return json.loads(sql(f"select public.recipe_issue('{session}','{request_id}');"))


def reserve(pair):
    session, request_id = pair
    return json.loads(sql(f"select public.recipe_reserve('{session}','{request_id}',"
                          f"'{('a'*64)}','{uuid.uuid4()}',70000);"))['code']


def race(pairs):
    with ThreadPoolExecutor(max_workers=16) as pool:
        return list(pool.map(reserve, pairs))


sql('create database ' + db + ';', 'postgres')
try:
    sql((ROOT/'supabase/migrations/20261105000000_ai_recipes.sql').read_text())
    sql((ROOT/'server_tests/sql_integration.sql').read_text())
    print('PASS migration, grants, replay, expiry, failure refunds, recovery and tombstone checks')

    reset()
    session = '1'*64
    request_id = str(uuid.uuid4())
    first = issue(session, request_id)
    second = issue(session, request_id)
    check(first['expires_at'] == second['expires_at'], 'issuance extended original validity')
    results = race([(session, request_id)] * 16)
    check(results.count('reserved') == 1 and results.count('in_progress') == 15, results)
    check(sql('select sum(reserved_micro) from recipe_private.budgets;') == '140000', 'duplicate budget reservation')
    print('PASS 16-way duplicate job: exactly one reservation and model lease')

    reset()
    pairs = [(session, str(uuid.uuid4())) for _ in range(16)]
    for pair in pairs:
        issue(*pair)
    results = race(pairs)
    check(results.count('reserved') == 1 and results.count('in_progress') == 15, results)
    print('PASS per-session concurrent limit under 16-way race')

    reset()
    pairs = [(session, str(uuid.uuid4())) for _ in range(16)]
    for pair in pairs:
        issue(*pair)
    sql(f"insert into recipe_private.quotas(session_hash,day,used) values('{session}',"
        "(clock_timestamp() at time zone 'Asia/Seoul')::date,4);")
    results = race(pairs)
    check(results.count('reserved') == 1 and results.count('daily_limit') == 15, results)
    check(sql('select used+reserved from recipe_private.quotas;') == '5', 'daily quota overspent')
    print('PASS fifth daily KST quota slot cannot be overspent under 16-way race')

    for daily, monthly, label in [(70000, 10_000_000, 'day'), (10_000_000, 70000, 'month')]:
        reset(daily, monthly)
        pairs = [(f'{i:064x}', str(uuid.uuid4())) for i in range(16)]
        for pair in pairs:
            issue(*pair)
        results = race(pairs)
        check(results.count('reserved') == 1 and results.count('budget_limit') == 15, results)
        print(f'PASS global {label} budget cannot be overspent under 16-way race')

    reset(concurrent=2)
    pairs = [(f'{i:064x}', str(uuid.uuid4())) for i in range(16)]
    for pair in pairs:
        issue(*pair)
    results = race(pairs)
    check(results.count('reserved') == 2 and results.count('rate_limited') == 14, results)
    print('PASS global concurrent limit under 16-way race')

    reset()
    def rate(_):
        return json.loads(sql("select public.recipe_rate_gate('"+'f'*64+"',5);"))['code']
    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(rate, range(32)))
    check(results.count('ok') == 5 and results.count('rate_limited') == 27, results)
    print('PASS atomic short IP limiter under 32-way race')
    print('ALL POSTGRES INTEGRATION CHECKS PASSED')
finally:
    sql('drop database ' + db + ' with (force);', 'postgres')
