#!/usr/bin/env python3
"""Generate src/rtl/cart/cart.v (Verilog-2001 for XST) from cart.sv and mappers/*.sv of NES_MiSTer.

Usage: gen_cart.py <NES_MiSTer/rtl> <mapper list> <out.v> [<work dir>]

The list names the instances of cart_top to keep (`vrc24`, `snd_vrc6`, ...), one per line, `#` comments.
The other instances are dropped and their outputs tied to 0. cart_top joins the outputs of its mappers
with tri-state buses (`tri0` / `tri1`, `assign x_b = enable ? x : 'hZ`), which XST does not take: here
every mapper drives its own wire with the default of the bus when it is not enabled (0, or all ones
for the data buses of `tri1`), and cart_top ORs (ANDs) them. A new output `cart_hit` says that one of
the kept mappers is enabled (the core takes the other mappers from its own MultiMapper meanwhile).
The work dir (default: next to the output, `cart_work`) gets the edited SV given to sv2v."""
import os, re, subprocess, sys

TRI0 = {'prg_allow_b': 1, 'vram_a10_b': 1, 'vram_ce_b': 1, 'chr_allow_b': 1, 'irq_b': 1,
        'prg_addr_b': 22, 'chr_addr_b': 22, 'flags_out_b': 16, 'audio_out_b': 16}
TRI1 = {'prg_dout_b': 8, 'chr_dout_b': 8}
TRI = dict(TRI0, **TRI1)
ONES_PORTS = ('prg_dout_b', 'chr_dout_b')   # tri1 ports of the mapper modules


def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), s, flags=re.S)
    return re.sub(r'//[^\n]*', '', s)


def match_paren(s, i):
    """index after the parenthesis closing the one at s[i]"""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(':
            depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0:
                return j + 1
    raise ValueError('unbalanced parenthesis')


def parse_ports(src):
    """{module: {port: direction}} of the ANSI headers of a file"""
    mods = {}
    clean = strip_comments(src)
    for m in re.finditer(r'\bmodule\s+(\w+)\s*', clean):
        i = m.end()
        if clean[i] == '#':
            i = match_paren(clean, clean.index('(', i))
            while clean[i].isspace():
                i += 1
        if clean[i] != '(':
            continue
        body = clean[i + 1:match_paren(clean, i) - 1]
        ports, d = {}, None
        for item in body.split(','):
            w = item.split()
            if not w:
                continue
            if w[0] in ('input', 'output', 'inout'):
                d = w[0]
            names = re.findall(r'\b([A-Za-z_]\w*)\b', item.split('=')[0])
            if names and d:
                ports[names[-1]] = d
        mods[m.group(1)] = ports
    return mods


def connections(block):
    """[(port, expr)] of an instance"""
    out, i = [], 0
    clean = strip_comments(block)
    while True:
        m = re.compile(r'\.(\w+)\s*\(').search(clean, i)
        if not m:
            return out
        end = match_paren(clean, m.end() - 1)
        out.append((m.group(1), clean[m.end():end - 1].strip()))
        i = end


def edit_mapper_source(src):
    """tri-state outputs of the mapper modules: inout -> output, 'hZ -> the default of the bus"""
    def default(name, width):
        return "{%s{1'b1}}" % width if name in ONES_PORTS else "%s'h0" % width

    def fix_assign(m):
        return 'assign %s = %s ? %s : %s;' % (m.group(1), m.group(2), m.group(3), default(m.group(1), m.group(4)))
    src = re.sub(r"assign\s+(\w+)\s*=\s*([\w\[\]]+)\s*\?\s*(.+?)\s*:\s*(\d+)'[hb][Zz]\s*;", fix_assign, src)
    if re.search(r"'[hb][Zz]", src):
        raise SystemExit('a tri-state left in a mapper: ' + re.search(r".*'[hb][Zz].*", src).group(0))
    # `always begin` without an event (combinational in Quartus) loops forever in a simulator
    src = re.sub(r'\balways(\s+begin)\b', r'always @*\1', src)
    src = re.sub(r'\binout(\s+(?:wire\s+)?(?:\[[^\]]*\]\s*)?\w+_b\b)', r'output\1', src)
    # an output bus the module does not drive (by an assign or a sub-instance): its default
    parts = re.split(r'(\bendmodule\b)', src)
    for k in range(0, len(parts), 2):
        text = parts[k]
        hdr = re.search(r'\bmodule\s+\w+', text)
        if not hdr:
            continue
        clean = strip_comments(text)
        add = []
        for m in re.finditer(r'\boutput\s+(?:wire\s+)?(?:\[(\d+):0\]\s*)?(\w+_b)\b', clean):
            name, width = m.group(2), int(m.group(1)) + 1 if m.group(1) else 1
            if not re.search(r'\bassign\s+%s\b|\(\s*%s\s*\)' % (name, name), clean):
                add.append('assign %s = %s;\n' % (name, default(name, width)))
        if add:
            parts[k] = text + ''.join(add)
    return ''.join(parts)


def edit_cart(src, keep, mods):
    lines = src.split('\n')
    out, hits, drive, i = [], [], {n: [] for n in TRI}, 0
    inst_re = re.compile(r'^(\w+)\s+(\w+)\s*(\(|$)')
    while i < len(lines):
        m = inst_re.match(lines[i])
        if not m or m.group(1) not in mods:
            out.append(lines[i])
            i += 1
            continue
        j = i
        while not re.match(r'^\s*\);', lines[j]):
            j += 1
        block = '\n'.join(lines[i:j + 1])
        mod, inst = m.group(1), m.group(2)
        conns = connections(block)
        if inst in keep:
            keep.discard(inst)
            for port, expr in conns:
                if expr in TRI:
                    wire = '%s__%s' % (expr, inst)
                    drive[expr].append(wire)
                    block = re.sub(r'\.%s(\s*)\(\s*%s\s*\)' % (port, expr), r'.%s\1(%s)' % (port, wire), block)
                    out.append('wire %s%s;' % ('[%d:0] ' % (TRI[expr] - 1) if TRI[expr] > 1 else '', wire))
                if port == 'enable' and 'prg_addr_b' in [e for _, e in conns]:
                    hits.append('(%s)' % expr)
            out.append(block)
        else:
            out.append('// %s %s: not in this core' % (mod, inst))
            for port, expr in conns:
                if mods[mod].get(port) in ('output', 'inout') and expr not in TRI \
                        and re.match(r'^\w+(\[\d+\])?$', expr):
                    out.append('assign %s = 0;' % expr)
        i = j + 1
    if keep:
        raise SystemExit('instances not in cart.sv: ' + ' '.join(sorted(keep)))
    text = '\n'.join(out)
    # the buses: wires joined by OR (tri0) or AND (tri1)
    decl = []
    for name, width in TRI.items():
        ones = name in TRI1
        w = '[%d:0] ' % (width - 1) if width > 1 else ''
        val = (' & ' if ones else ' | ').join(drive[name]) or ("{%d{1'b1}}" % width if ones else "%d'd0" % width)
        decl.append('wire %s%s = %s;' % (w, name, val))
    text = re.sub(r'^tri0[^\n]*\n|^tri1[^\n]*\n', '', text, flags=re.M)
    # declared after the instances that use them: the default nettype of Verilog would take them as 1 bit
    text = re.sub(r'(\nwire \[1023:0\] me;)', '\n' + '\n'.join(decl) + r'\1', text, count=1)
    text = re.sub(r'(\bmodule\s+cart_top\s*\()', r'\1\n\toutput            cart_hit,       // a mapper of this cart_top is enabled',
                  text, count=1)
    text = re.sub(r'\nendmodule\s*$', '\nassign cart_hit = %s;\n\nendmodule\n' % (' | '.join(hits) or "1'b0"), text)
    return text


def fix_wire_reg(outv, extra):
    """sv2v leaves `wire` on some signals the SV assigns in always blocks (XST HDLCompiler:1660):
    make them `reg`, from the PROCASSWIRE errors of a verilator lint, until there are none"""
    for _ in range(20):
        r = subprocess.run(['verilator', '--lint-only', '-Wno-fatal', '-Wno-WIDTH', '-Wno-UNUSED', '--top-module', 'cart_top',
                            outv] + extra, capture_output=True, text=True)
        errs = set((int(m.group(1)), m.group(2)) for m in
                   re.finditer(r"PROCASSWIRE: [^:]+:(\d+):\d+: .*'(\w+)'", r.stderr))
        if not errs:
            return
        lines = open(outv).read().split('\n')
        for ln, name in sorted(errs):
            for i in range(ln - 1, -1, -1):
                if lines[i].lstrip().startswith('module '):
                    raise SystemExit('no declaration of %s before line %d' % (name, ln))
                if re.match(r'\s*(output\s+)?reg\b[^;=]*\b%s\b' % re.escape(name), lines[i]):
                    break   # fixed by an earlier error of the same signal
                if re.match(r'\s*(output\s+)?wire\b[^;=]*\b%s\b' % re.escape(name), lines[i]):
                    lines[i] = re.sub(r'\bwire\b', 'reg', lines[i], count=1)
                    break
        open(outv, 'w').write('\n'.join(lines))
    raise SystemExit('PROCASSWIRE errors left')


def main():
    rtl, listfile, outv = sys.argv[1:4]
    work = sys.argv[4] if len(sys.argv) > 4 else os.path.join(os.path.dirname(os.path.abspath(outv)), 'cart_work')
    os.makedirs(work, exist_ok=True)
    keep = set()
    for line in open(listfile):
        keep.update(line.split('#')[0].split())
    srcs = [os.path.join(rtl, 'mappers', f) for f in sorted(os.listdir(os.path.join(rtl, 'mappers'))) if f.endswith('.sv')]
    srcs.append(os.path.join(rtl, 'EEPROM_24C0x.sv'))
    mods, files = {}, []
    for f in srcs:
        src = open(f).read()
        mods.update(parse_ports(src))
        dst = os.path.join(work, os.path.basename(f))
        open(dst, 'w').write('import regs_savestates::*;\n' + edit_mapper_source(src))
        files.append(dst)
    cart = os.path.join(work, 'cart.sv')
    open(cart, 'w').write('import regs_savestates::*;\n' + edit_cart(open(os.path.join(rtl, 'cart.sv')).read(), keep, mods))
    cmd = ['sv2v', '--top=cart_top', os.path.join(rtl, 'regs_savestates.sv')] + files + [cart, '-w', outv]
    subprocess.run(cmd, check=True)
    fix_wire_reg(outv, [os.path.join(os.path.dirname(os.path.abspath(outv)), 'eReg_SavestateV.v')])
    commit = subprocess.run(['git', '-C', rtl, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    body = open(outv).read()
    open(outv, 'w').write('// Generated by src/tools/upstream/gen_cart.py from NES_MiSTer %s (cart.sv, mappers/*.sv)\n'
                          '// with the instances of %s. Do not edit: change the list or the generator.\n%s'
                          % (commit, os.path.basename(listfile), body))


if __name__ == '__main__':
    main()
