#!/usr/bin/env python3
"""Every button and tappable view in the app has a name in the beta's event trail.

    python3 scripts/tap_ids.py --check   # lists anything unnamed; exits 1 if there is any
    python3 scripts/tap_ids.py --fix     # names it: .tapID("<file>.<label>") on buttons, TapRecorder.named on taps

A button is named when `.tapID(...)` follows it. Buttons inside menus, alerts, confirmation dialogs, context menus,
swipe actions and toolbars are left alone: modifiers there can stop them working, and the system names them anyway.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Roam"
SKIP_FILES = {"ComponentCatalogView.swift"}
SKIP_CONTEXT = re.compile(r"\.alert\s*\(|confirmationDialog|\bMenu\s*[({]|contextMenu|swipeActions|ToolbarItem|"
                          r"\.toolbar\s*\{|\bPicker\b")
BUTTON = re.compile(r"(?<![\w.])Button\s*[({]")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
TAP = re.compile(r"\.onTapGesture(\s*\(count:\s*\d+\))?\s*\{")


def match_close(text, i):
    """Index just past the bracket that closes the one at i, skipping strings and comments."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    stack = [pairs[text[i]]]
    j = i + 1
    while j < len(text) and stack:
        c = text[j]
        if c == '"':
            if text.startswith('"""', j):
                end = text.find('"""', j + 3)
                j = end + 3 if end >= 0 else len(text)
                continue
            j += 1
            depth = 0
            while j < len(text):
                if text[j] == "\\" and j + 1 < len(text) and text[j + 1] == "(":
                    depth += 1
                    j += 2
                    continue
                if depth and text[j] == ")":
                    depth -= 1
                elif text[j] == "\\":
                    j += 1
                elif text[j] == '"' and not depth:
                    break
                j += 1
            j += 1
            continue
        if text.startswith("//", j):
            j = text.find("\n", j)
            j = len(text) if j < 0 else j
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
        j += 1
    return j


def button_end(text, i):
    """End of a Button expression starting at i: its arguments, trailing closure and `label:` closure."""
    j = text.index("(", i) if text[text.index("Button", i) + 6:].lstrip().startswith("(") else text.index("{", i)
    j = match_close(text, j)
    while True:
        k = j
        while k < len(text) and text[k] in " \t":
            k += 1
        if k < len(text) and text[k] == "{":
            j = match_close(text, k)
            continue
        m = re.match(r"\s*\w+\s*:\s*\{", text[j:])
        if m and not text[j:j + m.end()].count("\n") > 1:
            j = match_close(text, j + m.end() - 1)
            continue
        return j


def enclosing_heads(text, pos):
    """The text just before each bracket that encloses pos."""
    heads, stack, j = [], [], 0
    while j < pos:
        c = text[j]
        if c == '"':
            end = text.find('"', j + 1)
            while end > 0 and text[end - 1] == "\\":
                end = text.find('"', end + 1)
            j = end + 1 if end > 0 else j + 1
            continue
        if text.startswith("//", j):
            j = text.find("\n", j)
            continue
        if c in "({":
            line_start = text.rfind("\n", 0, j) + 1
            stack.append(text[max(line_start, j - 120):j + 1])
        elif c in ")}" and stack:
            stack.pop()
        j += 1
    return stack


def inside_skipped_block(text, pos):
    """A backup to enclosing_heads: is there a menu, alert or dialog opener on a less-indented line just above?"""
    lines = text[:pos].split("\n")
    indent = len(lines[-1]) - len(lines[-1].lstrip())
    for line in reversed(lines[-14:-1]):
        stripped = line.lstrip()
        if not stripped:
            continue
        level = len(line) - len(stripped)
        if level < indent:
            if SKIP_CONTEXT.search(line):
                return True
            if not stripped.startswith(("Button", ".", "}", ")", "if ", "} else", "ForEach", "Group", "Section")):
                indent = level
    return False


def chain_after(text, j):
    """The modifier chain following an expression: lines that start with a dot."""
    rest = text[j:]
    lines = rest.split("\n")
    chain = [lines[0]]
    for line in lines[1:30]:
        if line.strip().startswith(".") or line.strip().startswith("//"):
            chain.append(line)
        else:
            break
    return "\n".join(chain)


def slug(value):
    value = re.sub(r"\\\(.*", "", value)
    value = re.sub(r"[^A-Za-z0-9]+", "-", value).strip("-").lower()
    return value[:40] or "button"


def name_for(file, expression, used):
    strings = STRING.findall(expression)
    label = next((s for s in strings if s and not s.startswith("\\(")), "button")
    base = f"{file.stem.lower()}.{slug(label)}"
    name, n = base, 2
    while name in used:
        name, n = f"{base}-{n}", n + 1
    used.add(name)
    return name


def scan(path, fix):
    text = path.read_text()
    used = set(re.findall(r'\.tapID\("([^"\\]+)"', text))
    edits, problems = [], []
    for m in BUTTON.finditer(text):
        start = m.start()
        line_start = text.rfind("\n", 0, start) + 1
        if text[line_start:start].lstrip().startswith("//"):
            continue
        if any(SKIP_CONTEXT.search(h) for h in enclosing_heads(text, start)) or inside_skipped_block(text, start):
            continue
        try:
            end = button_end(text, start)
        except ValueError:
            continue
        chain = chain_after(text, end)
        if ".tapID(" in chain:
            continue
        line = text.count("\n", 0, start) + 1
        identifier = re.search(r'\.accessibilityIdentifier\(', chain)
        if identifier:
            edits.append((end + identifier.start(), end + identifier.start() + len(".accessibilityIdentifier("), ".tapID("))
        else:
            edits.append((end, end, f'.tapID("{name_for(path, text[start:end], used)}")'))
        problems.append(f"{path.relative_to(ROOT.parent)}:{line}: button has no .tapID")
    for m in TAP.finditer(text):
        body = text[m.end():m.end() + 200]
        if "TapRecorder.named" in body.split("\n")[0] or "TapRecorder.named" in body[:120]:
            continue
        line = text.count("\n", 0, m.start()) + 1
        owner = re.findall(r"(?:var|func)\s+(\w+)", text[:m.start()])
        name = f"{path.stem.lower()}.{slug(owner[-1]) if owner else 'tap'}"
        n, base = 2, name
        while name in used:
            name, n = f"{base}-{n}", n + 1
        used.add(name)
        in_clause = re.match(r"\s*(\w+(\s*,\s*\w+)*\s+in\b)", body)
        at = m.end() + (in_clause.end() if in_clause else 0)
        edits.append((at, at, f' TapRecorder.named("{name}");'))
        problems.append(f"{path.relative_to(ROOT.parent)}:{line}: tap gesture isn't logged")
    if fix and edits:
        for a, b, new in sorted(edits, reverse=True):
            text = text[:a] + new + text[b:]
        path.write_text(text)
    return problems


def main():
    fix = "--fix" in sys.argv
    problems = []
    for path in sorted(ROOT.rglob("*.swift")):
        if path.name in SKIP_FILES or "Telemetry" in path.parts:
            continue
        problems += scan(path, fix)
    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} unnamed" + (" (named now)" if fix else ". Run python3 scripts/tap_ids.py --fix"))
        sys.exit(0 if fix else 1)
    print("Every button and tap is named.")


if __name__ == "__main__":
    main()
