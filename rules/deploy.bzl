"""Starlark rule for deploying a built site to a VPS via rsync.

Usage:
    load("//rules:deploy.bzl", "deploy")

    deploy(
        name = "deploy",
        site = ":site",           # a zola_site target
        remote_user = "deploy",
        remote_host = "myserver.example.com",
        remote_path = "/var/www/mysite",
    )

Then:
    bazel run //site:deploy
"""

def _deploy_impl(ctx):
    # Retrieve the output directory from the zola_site target.
    # DefaultInfo.files is a depset — convert to list to get the directory.
    site_files = ctx.attr.site[DefaultInfo].files.to_list()
    if len(site_files) != 1:
        fail("Expected exactly one output from site target (the public dir), got: %s" % site_files)

    site_dir = site_files[0]

    # Write a shell script that rsync-es the built site to the VPS.
    # This script becomes the executable for `bazel run`.
    script = ctx.actions.declare_file(ctx.attr.name + "_deploy.sh")

    ctx.actions.write(
        output = script,
        content = """#!/usr/bin/env bash
set -euo pipefail

# Resolve runfiles: Bazel passes the site dir as a runfile.
# $RUNFILES_DIR is set by Bazel when running via `bazel run`.
SITE_DIR="$RUNFILES_DIR/{workspace}/{site_short_path}"

REMOTE_USER="{remote_user}"
REMOTE_HOST="{remote_host}"
REMOTE_PATH="{remote_path}"
SSH_KEY="{ssh_key}"

echo "==> Deploying $SITE_DIR"
echo "    → $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"

RSYNC_OPTS="-avz --delete --checksum"

if [ -n "$SSH_KEY" ]; then
    RSYNC_OPTS="$RSYNC_OPTS -e 'ssh -i $SSH_KEY'"
fi

rsync $RSYNC_OPTS "$SITE_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"

echo "==> Done ✓"
""".format(
            workspace = ctx.workspace_name,
            site_short_path = site_dir.short_path,
            remote_user = ctx.attr.remote_user,
            remote_host = ctx.attr.remote_host,
            remote_path = ctx.attr.remote_path,
            ssh_key = ctx.attr.ssh_key,
        ),
        is_executable = True,
    )

    # The site directory must be a runfile so it is available when the
    # script executes under `bazel run`.
    runfiles = ctx.runfiles(files = [site_dir])

    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

deploy = rule(
    implementation = _deploy_impl,
    executable = True,
    doc = "Deploys a built Zola site to a remote VPS via rsync over SSH.",
    attrs = {
        "site": attr.label(
            mandatory = True,
            doc = "The zola_site target whose output to deploy.",
        ),
        "remote_user": attr.string(
            mandatory = True,
            doc = "SSH user on the remote host.",
        ),
        "remote_host": attr.string(
            mandatory = True,
            doc = "Hostname or IP of the remote VPS.",
        ),
        "remote_path": attr.string(
            default = "/var/www/site",
            doc = "Absolute path on the remote host to sync the site into.",
        ),
        "ssh_key": attr.string(
            default = "",
            doc = "Optional path to an SSH private key file (e.g. ~/.ssh/id_ed25519).",
        ),
    },
)
