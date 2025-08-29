import os
import subprocess
import sys


if __name__ == "__main__":
    argv = iter(sys.argv[1:])
    exe = next(argv)
    env = os.environ.copy()
    while (var := next(argv, "--")) != "--":
        k, v = var.split("=", 1)
        env[k] = v
    res = subprocess.run([exe] + list(argv), env=env)
    sys.exit(res.returncode)
