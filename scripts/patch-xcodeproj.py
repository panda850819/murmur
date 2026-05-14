#!/usr/bin/env python3
# Post-process Murmur.xcodeproj/project.pbxproj to fix an XcodeGen 2.45.4 bug:
# XCSwiftPackageProductDependency entries for products from local Swift packages
# are missing the `package = <XCLocalSwiftPackageReference>` linkage, so
# xcodebuild fails to resolve the module at compile time even though the
# package reference and Frameworks linkage are present.
#
# Run after `xcodegen generate`. Idempotent.
#
# Tracked upstream: see XcodeGen issue tracker for "local package product
# dependency missing package link". Remove this script when the upstream fix
# ships and we bump XcodeGen.

import re
import sys
from pathlib import Path

PBXPROJ = Path("Murmur.xcodeproj/project.pbxproj")

if not PBXPROJ.exists():
    sys.exit(f"ERROR: {PBXPROJ} not found — run `xcodegen generate` first")

content = PBXPROJ.read_text()

# Discover all XCLocalSwiftPackageReference entries: { name -> ref_id }
local_refs = {
    m.group(2): m.group(1)
    for m in re.finditer(
        r'(\w{24}) /\* XCLocalSwiftPackageReference "([^"]+)" \*/',
        content,
    )
}

if not local_refs:
    print("No XCLocalSwiftPackageReference entries found; nothing to patch.")
    sys.exit(0)

# For each local package, scan its Package.swift for product names so we can
# match XCSwiftPackageProductDependency entries to the correct package ref.
# Simple regex parse — assumes plain string literals in `.library(name: "...")`.
def package_products(pkg_dir: Path) -> list[str]:
    pkg_swift = pkg_dir / "Package.swift"
    if not pkg_swift.exists():
        return []
    text = pkg_swift.read_text()
    return re.findall(r'\.library\(\s*name:\s*"([^"]+)"', text)

# Build a flat map: product_name -> local_ref_id
product_to_ref: dict[str, tuple[str, str]] = {}
for pkg_name, ref_id in local_refs.items():
    products = package_products(Path(pkg_name))
    for product in products:
        product_to_ref[product] = (ref_id, pkg_name)

if not product_to_ref:
    print("No products found in local packages; nothing to patch.")
    sys.exit(0)

# Patch each XCSwiftPackageProductDependency that's missing a `package = X` line
patches_applied = 0
for product, (ref_id, pkg_name) in product_to_ref.items():
    # Match a XCSwiftPackageProductDependency block for this product that has
    # NO existing `package =` line.
    pattern = re.compile(
        r'(\w{24} /\* '
        + re.escape(product)
        + r' \*/ = \{\s*\n\s*isa = XCSwiftPackageProductDependency;\s*\n)'
        + r'(\s+productName = '
        + re.escape(product)
        + r';\s*\n\s+\};)',
        re.MULTILINE,
    )
    new_content, n = pattern.subn(
        r'\1\t\t\tpackage = '
        + ref_id
        + r' /* XCLocalSwiftPackageReference "'
        + pkg_name
        + r'" */;\n\2',
        content,
    )
    if n > 0:
        content = new_content
        patches_applied += n
        print(f"  patched: {product} -> XCLocalSwiftPackageReference \"{pkg_name}\" ({ref_id})")

if patches_applied == 0:
    print("Nothing to patch (all product dependencies already linked).")
    sys.exit(0)

PBXPROJ.write_text(content)
print(f"Patched {patches_applied} product dependency linkage(s) in {PBXPROJ}")
