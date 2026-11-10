#!/usr/bin/env python3
"""Add an app extension target to BikePlanner.xcodeproj, embedded in a host app target (#70).

Creates the target (Sources, Frameworks, Resources phases; Debug and Release configurations with the given build
settings), its product (.appex) in the Products group, a group for its directory (child of the main group) with the
given files (.m in Sources, the others only in the group), and in the host: a dependency on the new target and an
"Embed Foundation Extensions" copy phase (PlugIns).

Usage:
    scripts/xcode_add_target.py --name BikePlannerQuickLook --host BikePlanner \
        --setting PRODUCT_BUNDLE_IDENTIFIER=fr.free.daniel.braun.BikePlanner.QuickLook ... \
        BikePlannerQuickLook/PreviewProvider.m BikePlannerQuickLook/PreviewProvider.h BikePlannerQuickLook/Info.plist

Files live in the directory named after the target. Settings are written as given (quote values with spaces or
special characters yourself, e.g. 'INFOPLIST_KEY_CFBundleDisplayName="BikePlanner Quick Look"'; \\n and \\t
in a value are a new line and a tab, for a list: 'LD_RUNPATH_SEARCH_PATHS=(\\n\\t\\t\\t\\t\\t"$(inherited)",\\n\\t\\t\\t\\t)'). Shared sources
are added afterwards with scripts/xcode_add_files.py --target <name> --anchor <a .m of the target>.
A target is removed with scripts/xcode_remove_target.py.
"""
import argparse
import os
import re
import secrets
import sys

PBXPROJ = os.path.join(os.path.dirname(__file__), "..", "BikePlanner.xcodeproj", "project.pbxproj")

FILE_TYPES = {".m": "sourcecode.c.objc", ".h": "sourcecode.c.h", ".plist": "text.plist.xml",
              ".entitlements": "text.plist.entitlements"}


def new_id(text, taken):
    while True:
        i = secrets.token_hex(12).upper()
        if i not in text and i not in taken:
            taken.add(i)
            return i


def block(text, ident):
    """Return (start, end) of the '<ident> /* ... */ = { ... };' object (or '<ident> = {' without comment)."""
    m = re.search(r"^\t\t%s (/\*[^*]*\*/ )?= \{" % ident, text, re.M)
    if not m:
        sys.exit("object %s not found" % ident)
    end = text.index("\n\t\t};\n", m.end()) + len("\n\t\t};\n")
    return m.start(), end


def insert_in_section(text, section, entry):
    """Append entry (complete lines) at the end of a section, creating the section if needed."""
    end = "/* End %s section */" % section
    if end not in text:
        # sections are sorted by name: insert before the first section that comes after
        names = re.findall(r"^/\* Begin (\w+) section \*/", text, re.M)
        after = next((n for n in names if n > section), None)
        new = "/* Begin %s section */\n%s/* End %s section */\n\n" % (section, entry, section)
        anchor = "/* Begin %s section */" % after
        return text.replace(anchor, new + anchor, 1)
    return text.replace(end, entry + end, 1)


def append_to_list(text, ident, key, item):
    """Add `item` at the end of the list `key = ( ... );` of object `ident`."""
    s, e = block(text, ident)
    obj = text[s:e]
    m = re.search(r"(\n(\t+)%s = \(\n)((?:\2\t.*\n)*)(\2\);)" % re.escape(key), obj)
    if not m:
        sys.exit("%s of %s not found" % (key, ident))
    body = m.group(3) + m.group(2) + "\t" + item + ",\n"
    obj = obj[:m.start()] + m.group(1) + body + m.group(4) + obj[m.end():]
    return text[:s] + obj + text[e:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--host", required=True, help="app target that embeds the extension")
    ap.add_argument("--setting", action="append", default=[], help="KEY=VALUE build setting (both configurations)")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    name = args.name
    text = open(PBXPROJ).read()
    taken = set()

    if re.search(r"/\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % re.escape(name), text):
        sys.exit("target %s already exists" % name)
    hm = re.search(r"^\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % re.escape(args.host), text, re.M)
    if not hm:
        sys.exit("host target %s not found" % args.host)
    host = hm.group(1)
    project = re.search(r"^\t\t(\w{24}) /\* Project object \*/ = \{", text, re.M).group(1)
    ps, pe = block(text, project)
    main_group = re.search(r"mainGroup = (\w{24});", text[ps:pe]).group(1)
    products_group = re.search(r"productRefGroup = (\w{24})", text[ps:pe]).group(1)

    # files
    group_children = []
    sources = []
    for path in args.files:
        fname = os.path.basename(path)
        if os.path.dirname(os.path.normpath(path)) != name:
            sys.exit("%s: files must be in %s/" % (path, name))
        ext = os.path.splitext(fname)[1]
        if ext not in FILE_TYPES:
            sys.exit("unsupported file type: %s" % fname)
        ref = new_id(text, taken)
        text = insert_in_section(text, "PBXFileReference",
            '\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };\n'
            % (ref, fname, FILE_TYPES[ext], fname))
        group_children.append("%s /* %s */" % (ref, fname))
        if ext == ".m":
            bf = new_id(text, taken)
            text = insert_in_section(text, "PBXBuildFile",
                "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (bf, fname, ref, fname))
            sources.append("%s /* %s in Sources */" % (bf, fname))

    # product
    product = new_id(text, taken)
    appex = name + ".appex"
    text = insert_in_section(text, "PBXFileReference",
        '\t\t%s /* %s */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        'path = %s; sourceTree = BUILT_PRODUCTS_DIR; };\n' % (product, appex, appex))
    text = append_to_list(text, products_group, "children", "%s /* %s */" % (product, appex))

    # group
    group = new_id(text, taken)
    children = "".join("\t\t\t\t%s,\n" % c for c in group_children)
    text = insert_in_section(text, "PBXGroup",
        '\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\t\t\t);\n\t\t\tpath = %s;\n'
        '\t\t\tsourceTree = "<group>";\n\t\t};\n' % (group, name, children, name))
    text = append_to_list(text, main_group, "children", "%s /* %s */" % (group, name))

    # phases
    phase_ids = {}
    for phase, isa in (("Sources", "PBXSourcesBuildPhase"), ("Frameworks", "PBXFrameworksBuildPhase"),
                       ("Resources", "PBXResourcesBuildPhase")):
        pid = new_id(text, taken)
        files = "".join("\t\t\t\t%s,\n" % s for s in sources) if phase == "Sources" else ""
        text = insert_in_section(text, isa,
            "\t\t%s /* %s */ = {\n\t\t\tisa = %s;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (pid, phase, isa, files))
        phase_ids[phase] = pid

    # configurations
    settings = {}
    for s in args.setting:
        k, _, v = s.partition("=")
        settings[k] = v.replace("\\n", "\n").replace("\\t", "\t")  # a list on several lines
    conf_ids = []
    for conf in ("Debug", "Release"):
        cid = new_id(text, taken)
        body = "".join("\t\t\t\t%s = %s;\n" % (k, settings[k]) for k in sorted(settings))
        text = insert_in_section(text, "XCBuildConfiguration",
            "\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n"
            "\t\t\tname = %s;\n\t\t};\n" % (cid, conf, body, conf))
        conf_ids.append((cid, conf))
    clist = new_id(text, taken)
    text = insert_in_section(text, "XCConfigurationList",
        '\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {\n\t\t\tisa = XCConfigurationList;\n'
        "\t\t\tbuildConfigurations = (\n%s\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
        % (clist, name, "".join("\t\t\t\t%s /* %s */,\n" % c for c in conf_ids)))

    # target
    target = new_id(text, taken)
    text = insert_in_section(text, "PBXNativeTarget",
        '\t\t%s /* %s */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s /* Build configuration list '
        'for PBXNativeTarget "%s" */;\n\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n'
        "\t\t\t\t%s /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
        "\t\t\tname = %s;\n\t\t\tproductName = %s;\n\t\t\tproductReference = %s /* %s */;\n"
        '\t\t\tproductType = "com.apple.product-type.app-extension";\n\t\t};\n'
        % (target, name, clist, name, phase_ids["Sources"], phase_ids["Frameworks"], phase_ids["Resources"],
           name, name, product, appex))
    text = append_to_list(text, project, "targets", "%s /* %s */" % (target, name))
    ps, pe = block(text, project)
    proj = text[ps:pe]
    proj = re.sub(r"(\n\t\t\t\tTargetAttributes = \{\n)",
                  r"\g<1>\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 14.2;\n\t\t\t\t\t};\n" % target, proj, 1)
    text = text[:ps] + proj + text[pe:]

    # host: dependency and embedding
    proxy = new_id(text, taken)
    text = insert_in_section(text, "PBXContainerItemProxy",
        "\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = %s "
        "/* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = %s;\n\t\t};\n"
        % (proxy, project, target, name))
    dep = new_id(text, taken)
    text = insert_in_section(text, "PBXTargetDependency",
        "\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = %s /* %s */;\n"
        "\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n" % (dep, target, name, proxy))
    text = append_to_list(text, host, "dependencies", "%s /* PBXTargetDependency */" % dep)
    embed_bf = new_id(text, taken)
    text = insert_in_section(text, "PBXBuildFile",
        "\t\t%s /* %s in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = %s /* %s */; "
        "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\n" % (embed_bf, appex, product, appex))
    hs, he = block(text, host)
    em = re.search(r"(\w{24}) /\* Embed Foundation Extensions \*/", text[hs:he])
    if em:
        text = append_to_list(text, em.group(1), "files", "%s /* %s in Embed Foundation Extensions */" % (embed_bf, appex))
    else:
        embed = new_id(text, taken)
        text = insert_in_section(text, "PBXCopyFilesBuildPhase",
            "\t\t%s /* Embed Foundation Extensions */ = {\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
            '\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n'
            "\t\t\t\t%s /* %s in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (embed, embed_bf, appex))
        # right after Resources: a Run Script phase reading the built Info.plist (Set build info) must come after it
        hs, he = block(text, host)
        res = re.search(r"\n(\t+)(\w{24}) /\* Resources \*/,\n", text[hs:he])
        if res:
            at = hs + res.end()
            text = text[:at] + "%s%s /* Embed Foundation Extensions */,\n" % (res.group(1), embed) + text[at:]
        else:
            text = append_to_list(text, host, "buildPhases", "%s /* Embed Foundation Extensions */" % embed)

    open(PBXPROJ, "w").write(text)
    print("added target %s (%s), embedded in %s" % (name, target, args.host))


if __name__ == "__main__":
    main()
