#!/usr/bin/env python3
"""Remove native targets from BikePlanner.xcodeproj/project.pbxproj.

    scripts/xcode_remove_target.py BikePlanner_org BikePlanner_orgTests ...

Removes, for each target: the PBXNativeTarget, its build phases and their PBXBuildFile entries, its build
configuration list and configurations, its target dependencies and their container item proxies (also the
dependencies of other targets on it), its product reference, and its TargetAttributes entry. Source files and
their file references are not touched. Writes a .bak copy first.
"""
import re
import shutil
import sys
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "BikePlanner.xcodeproj" / "project.pbxproj"
ID = r"[0-9A-F]{24}"


def objects(text):
    """id -> body of each top-level object (two-tab indented `ID /* … */ = {…};`, one line or several)."""
    objs = {}
    lines = text.split("\n")
    start = re.compile(r"^\t\t(" + ID + r")\b.*= \{")
    i = 0
    while i < len(lines):
        m = start.match(lines[i])
        if not m:
            i += 1
            continue
        if lines[i].rstrip().endswith("};"):
            objs[m.group(1)] = lines[i]
            i += 1
            continue
        j = i + 1
        while j < len(lines) and lines[j] != "\t\t};":
            j += 1
        objs[m.group(1)] = "\n".join(lines[i:j + 1])
        i = j + 1
    return objs


def ids_in(body, key):
    m = re.search(r"\b" + key + r" = \((.*?)\);", body, re.S)
    return re.findall(ID, m.group(1)) if m else []


def id_of(body, key):
    m = re.search(r"\b" + key + r" = (" + ID + ")", body)
    return m.group(1) if m else None


def main(names):
    text = PBX.read_text()
    objs = objects(text)
    targets = {i: b for i, b in objs.items() if "isa = PBXNativeTarget;" in b}
    by_name = {re.search(r"\bname = \"?([^\";]+)\"?;", b).group(1): i for i, b in targets.items()}
    remove = set()
    for name in names:
        tid = by_name.get(name)
        if not tid:
            sys.exit(f"no target named {name}; targets: {', '.join(sorted(by_name))}")
        body = targets[tid]
        remove.add(tid)
        for phase in ids_in(body, "buildPhases"):
            remove.add(phase)
            remove.update(ids_in(objs.get(phase, ""), "files"))
        conf_list = id_of(body, "buildConfigurationList")
        if conf_list:
            remove.add(conf_list)
            remove.update(ids_in(objs.get(conf_list, ""), "buildConfigurations"))
        for dep in ids_in(body, "dependencies"):
            remove.add(dep)
            proxy = id_of(objs.get(dep, ""), "targetProxy")
            if proxy:
                remove.add(proxy)
        product = id_of(body, "productReference")
        if product:
            remove.add(product)
        # dependencies of other targets on this one, and proxies pointing to it
        for oid, ob in objs.items():
            if "isa = PBXTargetDependency;" in ob and id_of(ob, "target") == tid:
                remove.add(oid)
                proxy = id_of(ob, "targetProxy")
                if proxy:
                    remove.add(proxy)
            if "isa = PBXContainerItemProxy;" in ob and re.search(r"remoteGlobalIDString = " + tid, ob):
                remove.add(oid)

    shutil.copy(PBX, PBX.with_suffix(".pbxproj.bak"))
    lines = text.split("\n")
    out = []
    i = 0
    alt = "|".join(sorted(remove))
    start = re.compile(r"^(\t+)(" + alt + r")\b.*= \{")
    item = re.compile(r"^\t+(" + alt + r")\b[^=]*,$")
    while i < len(lines):
        line = lines[i]
        m = start.match(line)
        if m:
            indent = m.group(1)
            if line.rstrip().endswith("};"):        # one-line object
                i += 1
                continue
            i += 1                                   # skip the block up to its closing line
            while i < len(lines) and lines[i] != indent + "};":
                i += 1
            i += 1
            continue
        if item.match(line):                         # entry of a list: `ID /* … */,`
            i += 1
            continue
        out.append(line)
        i += 1
    PBX.write_text("\n".join(out))
    left = [x for x in remove if x in "\n".join(out)]
    print(f"removed {len(remove)} objects for: {', '.join(names)}")
    if left:
        print("warning: ids still referenced:", ", ".join(left))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
