#!/usr/bin/env python3
"""Validate target-to-local-package wiring that Xcode otherwise diagnoses late."""

from pathlib import Path
import re
import sys


PROJECT = Path(__file__).resolve().parents[1] / "SunnieDays.xcodeproj/project.pbxproj"
text = PROJECT.read_text(encoding="utf-8")


def object_body(identifier: str) -> str:
    match = re.search(rf"^\t\t{re.escape(identifier)} /\*.*?\*/ = \{{(.*?)^\t\t\}};", text, re.S | re.M)
    if not match:
        match = re.search(rf"^\t\t{re.escape(identifier)} /\*.*?\*/ = \{{(.*?)\}};$", text, re.M)
    if not match:
        raise AssertionError(f"missing project object {identifier}")
    return match.group(1)


def require(body: str, needle: str, context: str) -> None:
    if needle not in body:
        raise AssertionError(f"{context} is missing {needle}")


try:
    project = object_body("5D00000000000000000000A1")
    require(project, "5D00000000000000000000E0", "project package references")

    # Each consumer gets its own product dependency object. In particular, the
    # widget cannot rely on the containing app's dependency: extensions compile
    # and link as independent targets.
    consumers = {
        "SunnieDays": ("5D0000000000000000000101", "5D00000000000000000000E1", "5D0000000000000000000141", "5D00000000000000000000B1"),
        "SunnieDaysWatch": ("5D0000000000000000000102", "5D00000000000000000000E2", "5D0000000000000000000142", "5D00000000000000000000B2"),
        "SunnieDaysTests": ("5D0000000000000000000103", "5D00000000000000000000E3", "5D0000000000000000000143", "5D00000000000000000000B3"),
        "SunnieWidgets": ("5D0000000000000000000105", "5D00000000000000000000E5", "5D0000000000000000000145", "5D00000000000000000000B5"),
    }
    for name, (target_id, product_id, frameworks_id, build_file_id) in consumers.items():
        require(object_body(target_id), product_id, f"{name} package product dependencies")
        product = object_body(product_id)
        require(product, "5D00000000000000000000E0", f"{name} package product")
        require(product, "productName = SunnieShared;", f"{name} package product")
        require(object_body(frameworks_id), build_file_id, f"{name} Frameworks phase")
        require(object_body(build_file_id), product_id, f"{name} SunnieShared link entry")

    app = object_body("5D0000000000000000000101")
    require(app, "5D0000000000000000000184", "app target dependencies")
    widget_dependency = object_body("5D0000000000000000000184")
    require(widget_dependency, "5D0000000000000000000105", "widget target dependency")

    widget_group = object_body("5D0000000000000000000115")
    require(widget_group, "5D0000000000000000000123", "widget synchronized group")
    require(object_body("5D0000000000000000000123"), "target = 5D0000000000000000000105", "widget source membership")
except AssertionError as error:
    print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)

print("Xcode local-package dependencies are wired for all consuming targets.")
