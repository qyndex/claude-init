#!/usr/bin/env python3
"""Publish exact-head producer status; the App coordinator authenticates linked runs."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('producer', Path(__file__).with_name('factory-producer.py'))
producer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(producer)
def publish(api, repository, number, run_id, role, state_path, finish=None):
    root = f'repos/{repository}'
    producer.require(producer.coordinator.contract.integer(number) and producer.coordinator.contract.integer(run_id), 'positive PR/run identity required')
    if finish:
        state = producer.coordinator.contract.load(state_path)
        producer.require(state['repository'] == repository and state['pr'] == number and state['run_id'] == run_id and state['role'] == role, 'foreign check state')
        api.request(f'{root}/check-runs/{state["id"]}', method='PATCH', payload={
            'status': 'completed', 'conclusion': finish,
            'output': {'title': f'Factory {role}: {finish}', 'summary': f'Authenticated producer run {run_id}; candidate {state["head"]}'}})
    else:
        pr = api.get(f'{root}/pulls/{number}')
        producer.require(pr['head']['repo']['full_name'] == repository, 'foreign candidate')
        name = 'factory-verification' if role == 'verification' else 'factory-independent-review'
        check = api.post(f'{root}/check-runs', {'name': name, 'head_sha': pr['head']['sha'], 'status': 'in_progress',
                        'details_url': f'https://github.com/{repository}/actions/runs/{run_id}'})
        state_path.write_text(json.dumps({'repository': repository, 'pr': number, 'run_id': run_id,
                                         'head': pr['head']['sha'], 'role': role, 'id': check['id']}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--role', choices=['verification', 'review'], required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--pr', type=int, required=True)
    parser.add_argument('--run-id', type=int, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--finish', choices=['success', 'failure'])
    args = parser.parse_args()
    publish(producer.coordinator.GitHub(args.repository), args.repository, args.pr, args.run_id, args.role, args.state, args.finish)


if __name__ == '__main__':
    main()
