#!/usr/bin/env python3
"""Add a Run Script build phase to a target of BikePlanner.xcodeproj (companion of xcode_add_files.py).

The phase is appended to the target's build phases (i.e. after "Copy Bundle Resources") and runs on
every build ("Based on dependency analysis" off).

Usage:
    scripts/xcode_add_run_script.py --target BikePlanner --name "Set build info" \
        --input '$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)' --script '"${SRCROOT}/scripts/set_build_info.sh"'

The script is idempotent: a phase with the same name in the target is left as is.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from xcode_add_files import PBXPROJ, block, new_id  # noqa: E402


def quote(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--script", required=True, help="shell script (body of the phase)")
    ap.add_argument("--input", action="append", default=[], help="input path (dependency ordering)")
    args = ap.parse_args()

    text = open(PBXPROJ).read()
    m = re.search(r"^\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % re.escape(args.target), text, re.M)
    if not m:
        sys.exit("target %s not found" % args.target)
    ts, te = block(text, m.group(1))
    if "/* %s */" % args.name in text[ts:te]:
        print("skip (already in target): %s" % args.name)
        return

    pid = new_id(text)
    inputs = "".join("\t\t\t\t%s,\n" % quote(i) for i in args.input)
    phase = ("\t\t%s /* %s */ = {\n"
             "\t\t\tisa = PBXShellScriptBuildPhase;\n"
             "\t\t\talwaysOutOfDate = 1;\n"
             "\t\t\tbuildActionMask = 2147483647;\n"
             "\t\t\tfiles = (\n\t\t\t);\n"
             "\t\t\tinputFileListPaths = (\n\t\t\t);\n"
             "\t\t\tinputPaths = (\n%s\t\t\t);\n"
             "\t\t\tname = %s;\n"
             "\t\t\toutputFileListPaths = (\n\t\t\t);\n"
             "\t\t\toutputPaths = (\n\t\t\t);\n"
             "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
             "\t\t\tshellPath = /bin/sh;\n"
             "\t\t\tshellScript = %s;\n"
             "\t\t};\n") % (pid, args.name, inputs, quote(args.name), quote(args.script))

    if "/* End PBXShellScriptBuildPhase section */" in text:
        text = text.replace("/* End PBXShellScriptBuildPhase section */",
                            phase + "/* End PBXShellScriptBuildPhase section */", 1)
    else:
        text = text.replace("/* Begin PBXSourcesBuildPhase section */",
                            "/* Begin PBXShellScriptBuildPhase section */\n" + phase +
                            "/* End PBXShellScriptBuildPhase section */\n\n"
                            "/* Begin PBXSourcesBuildPhase section */", 1)

    ts, te = block(text, m.group(1))
    tb = text[ts:te]
    bp = tb.index("\t\t\tbuildPhases = (\n")
    end = tb.index("\t\t\t);\n", bp)
    tb = tb[:end] + "\t\t\t\t%s /* %s */,\n" % (pid, args.name) + tb[end:]
    text = text[:ts] + tb + text[te:]
    open(PBXPROJ, "w").write(text)
    print("added: %s" % args.name)


if __name__ == "__main__":
    main()
