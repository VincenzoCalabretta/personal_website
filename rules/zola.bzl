"""Starlark rules for building a Zola static site.

Usage:
    load("//rules:zola.bzl", "zola_site")

    zola_site(
        name = "site",
        config = "config.toml",
        srcs = glob([
            "config.toml",
            "content/**",
            "templates/**",
            "static/**",
        ]),
        overlays = {
            "//some:label": "relative/dest/path",
            "//dir:label": "relative/dest/dir/",  # trailing slash → copy into dir
        },
    )

Then:
    bazel build //site:site
    # output at bazel-bin/site/site_public/
"""

def _zola_site_impl(ctx):
    zola = ctx.executable.zola
    output_dir = ctx.actions.declare_directory(ctx.attr.name + "_public")
    site_root = ctx.file.config.dirname  # e.g. "site"

    # Build copy commands for overlay files (sourced outside the site tree)
    overlay_inputs = []
    overlay_cmds = []
    for target, dest_path in ctx.attr.overlays.items():
        for f in target.files.to_list():
            overlay_inputs.append(f)
            if dest_path.endswith("/"):
                cmd = (
                    'mkdir -p "$STAGING/{root}/{dest}" && ' +
                    'cp "{src}" "$STAGING/{root}/{dest}{name}"'
                ).format(
                    root = site_root,
                    dest = dest_path,
                    src = f.path,
                    name = f.basename,
                )
            else:
                cmd = (
                    'mkdir -p "$(dirname "$STAGING/{root}/{dest}")" && ' +
                    'cp "{src}" "$STAGING/{root}/{dest}"'
                ).format(
                    root = site_root,
                    dest = dest_path,
                    src = f.path,
                )
            overlay_cmds.append(cmd)

    srcs_joined = " ".join(['"%s"' % f.path for f in ctx.files.srcs])

    ctx.actions.run_shell(
        command = """\
set -euo pipefail

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Copy all site srcs into staging, preserving structure relative to site root.
for f in {srcs}; do
    rel="${{f#{root}/}}"
    dst="$STAGING/{root}/$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$f" "$dst"
done

# Place overlay files at their declared site-relative paths (overrides srcs).
{overlays}

"{zola}" --root "$STAGING/{root}" build \\
    --output-dir "{out}" \\
    --force
""".format(
            srcs = srcs_joined,
            root = site_root,
            overlays = "\n".join(overlay_cmds) if overlay_cmds else "# no overlays",
            zola = zola.path,
            out = output_dir.path,
        ),
        inputs = depset(ctx.files.srcs + overlay_inputs),
        tools = [zola],
        outputs = [output_dir],
        mnemonic = "ZolaBuild",
        progress_message = "Building Zola site %{label}",
    )

    return [DefaultInfo(
        files = depset([output_dir]),
        runfiles = ctx.runfiles(files = [output_dir]),
    )]

zola_site = rule(
    implementation = _zola_site_impl,
    doc = "Builds a Zola static site, producing a public/ directory of HTML.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "All site source files: content, templates, static, sass, themes.",
        ),
        "config": attr.label(
            allow_single_file = ["config.toml"],
            mandatory = True,
            doc = "The config.toml at the root of the Zola site.",
        ),
        "overlays": attr.label_keyed_string_dict(
            allow_files = True,
            default = {},
            doc = (
                "Extra files to inject at specific site-relative paths, sourced " +
                "from labels outside the site tree. A dest ending with '/' copies " +
                "each file into that directory; otherwise it is an exact dest path."
            ),
        ),
        "zola": attr.label(
            default = "//tools/zola",
            executable = True,
            cfg = "exec",
            doc = "The Zola binary to use. Defaults to //tools/zola.",
        ),
    },
)
