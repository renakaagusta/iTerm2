#!/usr/bin/env python3
"""iterm — control a running iTerm2 instance from the command line."""

from __future__ import annotations

import argparse
import os
import shlex
import sys


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="iterm",
        description="Control a running iTerm2 instance.",
    )
    sub = parser.add_subparsers(dest="command", metavar="command")
    sub.required = True

    # open
    p_open = sub.add_parser("open", help="Open path in a new tab (default: current directory)")
    p_open.add_argument(
        "path",
        nargs="?",
        default=".",
        help="Directory to open (default: .)",
    )

    # split-h / split-v
    sub.add_parser("split-h", help="Split current pane horizontally (new pane below)")
    sub.add_parser("split-v", help="Split current pane vertically (new pane to the right)")

    # new-window
    sub.add_parser("new-window", help="Open a new iTerm2 window")

    # close
    sub.add_parser("close", help="Close current tab (closes window if it is the last tab)")

    # rename
    p_rename = sub.add_parser("rename", help="Rename the current session")
    p_rename.add_argument("name", nargs="?", default=None,
                          help="New session name (omit to clear custom name)")

    return parser


async def _run(connection: object, args: argparse.Namespace) -> None:
    import iterm2  # type: ignore[import]

    app = await iterm2.async_get_app(connection)

    # new-window doesn't need a focused window
    if args.command == "new-window":
        await iterm2.Window.async_create(connection)
        return

    window = app.current_terminal_window
    if window is None:
        print("iterm: no window is currently focused", file=sys.stderr)
        sys.exit(1)

    tab = window.current_tab
    if tab is None:
        print("iterm: no tab is currently focused", file=sys.stderr)
        sys.exit(1)

    session = tab.current_session
    if session is None:
        print("iterm: no session is currently focused", file=sys.stderr)
        sys.exit(1)

    if args.command == "open":
        path = os.path.abspath(os.path.expanduser(args.path))
        new_tab = await window.async_create_tab()
        new_session = new_tab.current_session
        await new_session.async_send_text(f"cd {shlex.quote(path)}\n")

    elif args.command == "split-h":
        # vertical=False → horizontal divider → new pane below
        await session.async_split_pane(vertical=False)

    elif args.command == "split-v":
        # vertical=True → vertical divider → new pane to the right
        await session.async_split_pane(vertical=True)

    elif args.command == "close":
        await session.async_close(force=False)

    elif args.command == "rename":
        profile = await session.async_get_profile()
        new_name = args.name if args.name is not None else (profile.name or "")
        write_only = iterm2.LocalWriteOnlyProfile()
        write_only.set_name(new_name)
        await session.async_set_profile_properties(write_only)


def main() -> None:
    import iterm2  # type: ignore[import]

    parser = _build_parser()
    args = parser.parse_args()

    try:
        iterm2.run_until_complete(lambda conn: _run(conn, args))
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:  # noqa: BLE001
        print(f"iterm: {exc}", file=sys.stderr)
        print("Tip: make sure iTerm2 is running.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
