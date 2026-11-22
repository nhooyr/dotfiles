"""Call logging shared by the isolated GitHub helper tests."""

import os


def git_command(args):
    index = 0
    while index < len(args):
        if args[index] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"):
            index += 2
        elif args[index].startswith("-"):
            index += 1
        else:
            break
    return args[index] if index < len(args) else ""


def read_calls(path):
    """Read NUL-separated calls with an argument count to preserve empty args."""
    if not path.exists():
        return []
    fields = iter(os.fsdecode(path.read_bytes()).split("\0")[:-1])
    calls = []
    for kind in fields:
        args = [next(fields) for _ in range(int(next(fields)))]
        call = {"kind": kind, "args": args}
        if kind == "git":
            call["command"] = git_command(args)
        calls.append(call)
    return calls
