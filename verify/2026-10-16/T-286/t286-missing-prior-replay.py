from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
setup=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
text=Path('.claude/scripts/test/factory-receipt-coverage.sh').read_text()
prior=text.split("prior=r'''\n",1)[1].split("'''\nexec(compile(fixture+empty_setup+prior",1)[0]
exec(compile(fixture+setup+prior,'actual-shipped-prior-attempt-case','exec'))
