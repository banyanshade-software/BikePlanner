#!/usr/bin/env python3
"""Set build settings of a target, in all its configurations (Debug and Release), in project.pbxproj.

    scripts/xcode_set_build_setting.py --target RideAnalyzer ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon

A setting already there is replaced; values are written quoted when they need it. Use this rather than editing
project.pbxproj by hand.
"""
import argparse
import os
import re
import sys

PBXPROJ = os.path.join(os.path.dirname(__file__), "..", "BikePlanner.xcodeproj", "project.pbxproj")


def block(text, ident):
    m = re.search(r"^\t\t%s /\*[^*]*\*/ = \{" % ident, text, re.M)
    if not m:
        sys.exit("object %s not found" % ident)
    end = text.index("\n\t\t};\n", m.end()) + len("\n\t\t};\n")
    return m.start(), end


def quoted(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./$()-]+", value) else '"%s"' % value.replace('"', '\\"')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("settings", nargs="+", help="KEY=VALUE")
    args = ap.parse_args()
    text = open(PBXPROJ).read()
    m = re.search(r"^\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % re.escape(args.target), text, re.M)
    if not m:
        sys.exit("target %s not found" % args.target)
    ts, te = block(text, m.group(1))
    list_id = re.search(r"buildConfigurationList = (\w{24})", text[ts:te]).group(1)
    ls, le = block(text, list_id)
    configs = re.findall(r"^\t\t\t\t(\w{24}) /\*", text[ls:le], re.M)
    for config in configs:
        cs, ce = block(text, config)
        conf = text[cs:ce]
        for setting in args.settings:
            key, _, value = setting.partition("=")
            line = "\t\t\t\t%s = %s;\n" % (key, quoted(value))
            if re.search(r"^\t\t\t\t%s = " % re.escape(key), conf, re.M):
                conf = re.sub(r"^\t\t\t\t%s = [^\n]*\n" % re.escape(key), lambda _: line, conf, flags=re.M)
            else:
                conf = conf.replace("\t\t\tbuildSettings = {\n", "\t\t\tbuildSettings = {\n" + line, 1)
        text = text[:cs] + conf + text[ce:]
        print("%s: %s" % (re.search(r"/\* (\w+) \*/", conf).group(1), ", ".join(args.settings)))
    open(PBXPROJ, "w").write(text)


if __name__ == "__main__":
    main()
