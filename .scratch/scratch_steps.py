# Throwaway: give every self-hosted job a workspace TMPDIR and clear it after. Not committed.
import re, sys

SETUP = """{i}- name: Scratch in the workspace, not the runner's shared /tmp
{i}  # /tmp is a RAM disk every build on the machine shares; when it filled on
{i}  # 2026-09-24 a compiler died and a job hung for hours instead of failing.
{i}  run: |
{i}    mkdir -p "$GITHUB_WORKSPACE/.tmp"
{i}    echo "TMPDIR=$GITHUB_WORKSPACE/.tmp" >> "$GITHUB_ENV"
"""
CLEAR = """{i}- name: Clear scratch
{i}  if: always()
{i}  run: rm -rf "$GITHUB_WORKSPACE/.tmp"
"""

def indent(l): return len(l) - len(l.lstrip(' '))

def transform(text):
    lines = text.split('\n')
    if 'GITHUB_WORKSPACE/.tmp' in text: return text, []
    ji = next(i for i, l in enumerate(lines) if l.rstrip() == 'jobs:')
    # job headers: indent 2 keys after jobs:
    heads = [i for i in range(ji + 1, len(lines)) if lines[i].strip() and not lines[i].lstrip().startswith('#') and indent(lines[i]) == 2]
    heads.append(len(lines))
    edits = []
    for a, b in zip(heads, heads[1:]):
        block = lines[a:b]
        ro = [l for l in block if l.strip().startswith('runs-on:')]
        if not ro: continue
        target = 'self-hosted' in ro[0] or ('matrix.os' in ro[0] and 'self-hosted' in '\n'.join(block))
        if not target: continue
        si = next((a + k for k, l in enumerate(block) if l.strip() == 'steps:'), None)
        if si is None: continue
        items = [k for k in range(si + 1, b) if lines[k].lstrip().startswith('- ') and indent(lines[k]) > indent(lines[si])]
        step_ind = min(indent(lines[k]) for k in items)
        items = [k for k in items if indent(lines[k]) == step_ind]
        # end of steps list: last non-empty line of the job that is deeper than steps:
        end = b
        while end - 1 > si and (not lines[end - 1].strip()): end -= 1
        # checkout step
        co = next((n for n, k in enumerate(items) if any('actions/checkout' in lines[x] for x in range(k, (items[n + 1] if n + 1 < len(items) else end)))), None)
        at = (items[co + 1] if co + 1 < len(items) else end) if co is not None else items[0]
        # Above the next step's own leading comments, which belong to it.
        while at - 1 > si and (lines[at - 1].lstrip().startswith('#') or not lines[at - 1].strip()):
            at -= 1
        edits.append((at, SETUP.format(i=' ' * step_ind)))
        edits.append((end, CLEAR.format(i=' ' * step_ind)))
    for at, txt in sorted(edits, key=lambda e: e[0], reverse=True):
        lines[at:at] = txt.rstrip('\n').split('\n')
    return '\n'.join(lines), edits

if __name__ == '__main__':
    write = sys.argv[1] == '--write'
    for f in sys.argv[2:]:
        src = open(f).read()
        out, edits = transform(src)
        print(f'{f}: {len(edits)//2} job(s)')
        if write and edits: open(f, 'w').write(out)
