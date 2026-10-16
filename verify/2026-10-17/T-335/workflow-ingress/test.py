"""AC-6/8 source-only ingress contract; no minting or remote requests."""
from pathlib import Path
import os
import subprocess
import tempfile
import yaml

ROOT = Path.cwd()
BASE = '7d1238224017a77c5b4aff9ada4d09435de3c5c2'
FILES = ('factory-hosted-digest.yml', 'factory-reporting-alerts.yml', 'factory-reporting-queue.yml', 'factory-hosted-feedback.yml')
PIN = 'actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1'
FLAG = "${{ vars.FACTORY_REPORTING_APP_WRITER_ENABLED || 'false' }}"
TOKEN = '${{ steps.reporting_app.outputs.token }}'
for name in FILES:
    path = ROOT/'.github/workflows'/name
    old = yaml.load(subprocess.check_output(['git','show',BASE+':.github/workflows/'+name]), Loader=yaml.BaseLoader)
    new = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
    assert set(new) == set(old), name
    for key in ('on','permissions','concurrency'):
        assert new[key] == old[key], (name,key)
    oldjob, = old['jobs'].values()
    job, = new['jobs'].values()
    for key in ('if','environment','runs-on','timeout-minutes'):
        assert job[key] == oldjob[key], (name,key)
    assert job['environment'] == 'factory-reporting'
    assert job.get('env') == {'FACTORY_REPORTING_APP_WRITER_ENABLED':FLAG,
                          'FACTORY_REPORTING_APP_ID':'${{ vars.FACTORY_REPORTING_APP_ID }}',
                          'FACTORY_REPORTING_STATE_REPOSITORY':'${{ vars.FACTORY_REPORTING_STATE_REPOSITORY || github.repository }}'}, name
    mint, = (step for step in job['steps'] if step.get('id') == 'reporting_app')
    assert mint['uses'] == PIN and "env.FACTORY_REPORTING_APP_WRITER_ENABLED == 'true'" in mint['if']
    assert mint['with'] == {'app-id':'${{ vars.FACTORY_REPORTING_APP_ID }}',
                           'private-key':'${{ secrets.FACTORY_REPORTING_APP_PRIVATE_KEY }}',
                           'owner':'${{ github.repository_owner }}',
                           'repositories':'${{ github.event.repository.name }}',
                           'permission-contents':'write','permission-administration':'read'}, name
    assert 'continue-on-error' not in mint
    validator, = (step for step in job['steps'] if step.get('name') == 'Validate selected reporting credentials')
    assert validator['env'] == {'GH_TOKEN':'${{ github.token }}','FACTORY_REPORTING_APP_TOKEN':TOKEN}, name
    original_steps = [step for step in job['steps'] if step not in (mint,validator)]
    assert len(original_steps)==len(oldjob['steps'])
    for original,current in zip(oldjob['steps'],original_steps):
        compare = dict(current)
        if 'GH_TOKEN' in original.get('env',{}):
            assert current['env']['GH_TOKEN'] == '${{ github.token }}'
            assert current['env']['FACTORY_REPORTING_APP_TOKEN'] == TOKEN
            compare['env'] = {key:value for key,value in current['env'].items() if key!='FACTORY_REPORTING_APP_TOKEN'}
            if name == 'factory-reporting-queue.yml':
                assert current['env']['FACTORY_REPORTING_STATE_REPOSITORY'] == '${{ vars.FACTORY_REPORTING_STATE_REPOSITORY || github.repository }}'
                compare['env']['FACTORY_REPORTING_STATE_REPOSITORY'] = original['env']['FACTORY_REPORTING_STATE_REPOSITORY']
        else:
            assert 'FACTORY_REPORTING_APP_TOKEN' not in current.get('env',{})
        assert compare == original, (name,original.get('name'))
    assert sum('FACTORY_REPORTING_APP_PRIVATE_KEY' in str(step) for step in job['steps']) == 1
    assert all('FACTORY_APP_PRIVATE_KEY' not in str(step) for step in job['steps'])
    if name == 'factory-reporting-alerts.yml':
        assert "vars.FACTORY_REPORTING_MONITOR_ENABLED == 'true'" in mint['if']
        assert validator['if'] == "vars.FACTORY_REPORTING_MONITOR_ENABLED == 'true'"
    script = validator['run'].split("<<'PYWRITER'\n",1)[1].rsplit('\nPYWRITER',1)[0]
    with tempfile.TemporaryDirectory() as tmp:
        marker=Path(tmp)/'unexpected-api'
        stub=Path(tmp)/'gh';stub.write_text('#!/bin/sh\ntouch "'+str(marker)+'"\nexit 99\n');stub.chmod(0o755)
        env=dict(HOME=tmp,GITHUB_REPOSITORY='org/repo',FACTORY_REPORTING_STATE_REPOSITORY='org/repo',GH_TOKEN='source-fixture',PATH=tmp+os.pathsep+os.environ['PATH'])
        for updates,success in (({},True),({'FACTORY_REPORTING_APP_WRITER_ENABLED':'false'},True),
                                ({'FACTORY_REPORTING_APP_WRITER_ENABLED':'true','FACTORY_REPORTING_APP_ID':'5340785','FACTORY_REPORTING_APP_TOKEN':'writer-fixture'},True),
                                ({'FACTORY_REPORTING_APP_WRITER_ENABLED':'TRUE'},False),
                                ({'FACTORY_REPORTING_APP_WRITER_ENABLED':'true','FACTORY_REPORTING_APP_ID':'5340785','FACTORY_REPORTING_STATE_TOKEN':'legacy-fixture'},False),
                                ({'FACTORY_REPORTING_APP_WRITER_ENABLED':'true','FACTORY_REPORTING_APP_TOKEN':'writer-fixture'},False)):
            actual=dict(env,**updates)
            result=subprocess.run(['python3','-'],input=script,text=True,capture_output=True,env=actual,cwd=ROOT,timeout=10)
            assert (result.returncode==0)==success,(name,updates,result.stderr)
            assert 'source-fixture' not in result.stdout+result.stderr and 'writer-fixture' not in result.stdout+result.stderr
            assert not marker.exists(), 'credential validation called a remote transport'
print('PASS four workflow boundaries and 24 actual no-network credential selection scenarios')
