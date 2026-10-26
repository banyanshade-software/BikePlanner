#!/usr/bin/env python3
"""Add source files to a target of BikePlanner.xcodeproj.

The new files are put in the same group as an existing "anchor" file that already
belongs to the target, and added to the target's Sources build phase
(.m / .c files) or just to the group (.h files).

Usage:
    scripts/xcode_add_files.py --target BikePlannerTests --anchor BikePlannerTests.m \
        BikePlannerTests/GPXParserTests.m BikePlannerTests/Fixtures.h

Paths are relative to the repository root; new files must live in the anchor's directory.
A file that is already referenced elsewhere in the project (group whose path is the file's
directory) is reused and only added to the target's Sources (e.g. a test helper shared by
BikePlannerTests and BikePlannerUITests). The script is idempotent.
"""
import argparse
import os
import re
import secrets
import sys

PBXPROJ = os.path.join(os.path.dirname(__file__), "..", "BikePlanner.xcodeproj", "project.pbxproj")

FILE_TYPES = {".m": "sourcecode.c.objc", ".h": "sourcecode.c.h", ".c": "sourcecode.c.c"}


def new_id(text):
    while True:
        i = secrets.token_hex(12).upper()
        if i not in text:
            return i


def block(text, ident):
    """Return (start, end) of the '<ident> /* ... */ = { ... };' object."""
    m = re.search(r"^\t\t%s /\*[^*]*\*/ = \{" % ident, text, re.M)
    if not m:
        sys.exit("object %s not found" % ident)
    end = text.index("\n\t\t};\n", m.end()) + len("\n\t\t};\n")
    return m.start(), end


def add_build_file(text, sources_id, ref, name):
    bf = new_id(text)
    text = text.replace(
        "/* End PBXBuildFile section */",
        "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
        "/* End PBXBuildFile section */" % (bf, name, ref, name), 1)
    ss, se = block(text, sources_id)
    sb = text[ss:se].replace("\t\t\t);\n", "\t\t\t\t%s /* %s in Sources */,\n\t\t\t);\n" % (bf, name), 1)
    return text[:ss] + sb + text[se:]


def find_existing_ref(text, name, dirname):
    """fileRef of `name` in a group whose path is `dirname`, or None"""
    for ref in re.findall(r"^\t\t(\w{24}) /\* %s \*/ = \{isa = PBXFileReference;" % re.escape(name), text, re.M):
        for gm in re.finditer(r"^\t\t(\w{24}) /\*[^*]*\*/ = \{\n\t\t\tisa = PBXGroup;", text, re.M):
            gs, ge = block(text, gm.group(1))
            if ref in text[gs:ge] and re.search(r"\bpath = %s;" % re.escape(dirname), text[gs:ge]):
                return ref
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--anchor", required=True, help="file name already in the target")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    text = open(PBXPROJ).read()

    # target -> Sources phase id
    m = re.search(r"^\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % re.escape(args.target), text, re.M)
    if not m:
        sys.exit("target %s not found" % args.target)
    ts, te = block(text, m.group(1))
    sources_id = re.search(r"(\w{24}) /\* Sources \*/", text[ts:te]).group(1)
    ss, se = block(text, sources_id)
    sources_block = text[ss:se]

    # anchor fileRef belonging to that target
    anchor_ref = None
    for bf in re.findall(r"(\w{24}) /\* %s in Sources \*/" % re.escape(args.anchor), sources_block):
        r = re.search(r"%s /\*[^*]*\*/ = \{isa = PBXBuildFile; fileRef = (\w{24})" % bf, text)
        if r:
            anchor_ref = r.group(1)
    if not anchor_ref:
        sys.exit("anchor %s not in target %s" % (args.anchor, args.target))

    # group containing the anchor
    g = None
    for gm in re.finditer(r"^\t\t(\w{24}) /\*[^*]*\*/ = \{\n\t\t\tisa = PBXGroup;", text, re.M):
        gs, ge = block(text, gm.group(1))
        if anchor_ref in text[gs:ge]:
            g = gm.group(1)
            break
    if not g:
        sys.exit("group of anchor not found")

    for path in args.files:
        name = os.path.basename(path)
        ext = os.path.splitext(name)[1]
        if ext not in FILE_TYPES:
            sys.exit("unsupported file type: %s" % name)
        gs, ge = block(text, g)
        if "/* %s */" % name in text[gs:ge]:
            print("skip (already in project): %s" % name)
            continue
        existing = find_existing_ref(text, name, os.path.basename(os.path.dirname(os.path.normpath(path))))
        if existing:
            ss, se = block(text, sources_id)
            in_target = any(re.search(r"%s /\*[^*]*\*/ = \{isa = PBXBuildFile; fileRef = %s" % (b, existing), text)
                            for b in re.findall(r"(\w{24}) /\* %s in Sources \*/" % re.escape(name), text[ss:se]))
            if ext == ".h" or in_target:
                print("skip (already in target): %s" % name)
                continue
            text = add_build_file(text, sources_id, existing, name)
            print("added to target (existing file): %s" % name)
            continue
        ref = new_id(text)
        text = text.replace(
            "/* End PBXFileReference section */",
            '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };\n'
            "/* End PBXFileReference section */" % (ref, name, FILE_TYPES[ext], name), 1)
        gs, ge = block(text, g)
        grp = text[gs:ge]
        grp = grp.replace("\t\t\t);\n", "\t\t\t\t%s /* %s */,\n\t\t\t);\n" % (ref, name), 1)
        text = text[:gs] + grp + text[ge:]
        if ext != ".h":
            text = add_build_file(text, sources_id, ref, name)
        print("added: %s" % name)

    open(PBXPROJ, "w").write(text)


if __name__ == "__main__":
    main()
