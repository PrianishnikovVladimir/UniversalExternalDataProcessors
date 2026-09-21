"""Выдаёт секцию vm из .v8-project.json в виде присваиваний для eval в bash."""
import json
import shlex
import sys

КЛЮЧИ = (("ssh", "SSH_HOST"), ("v8", "V8"), ("ib", "IB"), ("user", "IB_USER"), ("password", "IB_PWD"), ("projectWin", "PROJ_WIN"))

vm = json.load(open(sys.argv[1], encoding="utf-8")).get("vm")
if not vm:
	sys.exit("в .v8-project.json нет секции vm")

for ключ, переменная in КЛЮЧИ:
	print(f"{переменная}={shlex.quote(vm[ключ])}")
