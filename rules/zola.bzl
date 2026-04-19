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
            "sass/**",
            "themes/**",
        ]),
    )

Then:
    bazel build //site:site
    # output at bazel-bin/site/public/
"""

def _zola_site_impl(ctx):
    zola = ctx.executable.zola
    output_dir = ctx.actions.declare_directory(ctx.attr.name + "_public")

    # The root is the directory containing config.toml
    site_root = ctx.file.config.dirname

    ctx.actions.run_shell(
        command = """
set -euo pipefail

ZOLA="{zola}"
ROOT="{root}"
OUT="{out}"

# Zola requires the output dir to not exist or be empty when using --force.
# Bazel pre-creates declared directories, so we pass --force.
"$ZOLA" --root "$ROOT" build \\
    --output-dir "$OUT" \\
    --force
""".format(
            zola = zola.path,
            root = site_root,
            out = output_dir.path,
        ),
        inputs = depset(
            ctx.files.srcs,
            transitive = [],
        ),
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
        "zola": attr.label(
            default = "//tools/zola",
            executable = True,
            cfg = "exec",
            doc = "The Zola binary to use. Defaults to //tools/zola.",
        ),
    },
)
