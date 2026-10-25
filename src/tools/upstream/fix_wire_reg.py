#!/usr/bin/env python3
"""Turn the `wire` declarations of sv2v output into `reg` where XST reports a procedural assignment
(HDLCompiler:1660). Usage: fix_wire_reg.py <file.v> <xst .syr>; prints the number of fixes."""
import re, sys
src, syr = sys.argv[1], sys.argv[2]
lines = open(src).read().split("\n")
errs = set()
for m in re.finditer(r'Line (\d+): Procedural assignment to a non-register (\w+)', open(syr).read()):
    errs.add((int(m.group(1)), m.group(2)))
fixed = 0
for ln, name in sorted(errs):
    # the declaration before the line, inside the same module
    for i in range(ln - 1, -1, -1):
        if lines[i].lstrip().startswith("module "):
            break
        if re.match(r'\s*(output\s+)?wire\b[^;=]*\b%s\b' % re.escape(name), lines[i]):
            lines[i] = re.sub(r'\bwire\b', 'reg', lines[i], count=1)
            fixed += 1
            break
open(src, "w").write("\n".join(lines))
print(fixed)
