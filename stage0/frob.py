"""Tiny interpreter for manipulating downloaded artifacts and sysroots."""

import os
import subprocess
import shutil
import sys
from pathlib import Path


if __name__ == "__main__":
    symbols = {}

    def parse(string):
        path = Path()
        for component in string.split("/"):
            if component.startswith("{") and component.endswith("}"):
                path = path / symbols[component[1:-1]]
            elif component == "?":
                entries = list(path.iterdir())
                if len(entries) != 1:
                    unexpected = [entry.name for entry in entries]
                    msg = "unexpected directory entries: {}".format(unexpected)
                    raise RuntimeError(msg)
                path = entries[0]
            else:
                path = path / component
        return path

    argv = iter(sys.argv[1:])
    while (instruction := next(argv, None)) is not None:
        if "=" in instruction:
            name, value = instruction.split("=", 1)
            symbols[name] = parse(value)
        elif instruction == "--basename":
            name, path = next(argv).split("=", 1)
            symbols[name] = parse(path).name
        elif instruction == "--cp":
            source, dest = parse(next(argv)), parse(next(argv))
            shutil.copy2(source, dest)
        elif instruction == "--elaborate":
            link = parse(next(argv))
            target = link.readlink()
            link.unlink()
            link.mkdir()
            for f in (link.parent / target).iterdir():
                (link / f.name).symlink_to(".." / target / f.name)
        elif instruction == "--exec":
            exe = parse(next(argv))
            env = os.environ.copy()
            while (var := next(argv, "--")) != "--":
                k, v = var.split("=", 1)
                env[k] = v
            res = subprocess.run([exe] + list(argv), env=env)
            sys.exit(res.returncode)
        elif instruction == "--mkdir":
            parse(next(argv)).mkdir()
        elif instruction == "--read":
            name, path = next(argv).split("=", 1)
            with open(parse(path)) as f:
                symbols[name] = f.read().strip()
        elif instruction == "--symlink":
            target, link = parse(next(argv)), parse(next(argv))
            link.symlink_to(target)
        else:
            raise RuntimeError(instruction)
