"""Canonical offline release CLI."""

from __future__ import annotations

import argparse
from pathlib import Path

from .bundle import build as build_cpu
from .gpu import build as build_gpu
from .verify import (
    verify_cpu,
    verify_gpu,
    verify_pair,
)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="python -m tools.release"
    )

    commands = parser.add_subparsers(
        dest="command",
        required=True,
    )

    build_parser = (
        commands.add_parser(
            "build"
        )
    )

    build_parser.add_argument(
        "kind",
        choices=(
            "cpu",
            "gpu",
        ),
    )

    build_parser.add_argument(
        "--version",
    )

    build_parser.add_argument(
        "--dist",
        type=Path,
        default=Path("dist"),
    )

    verify_parser = (
        commands.add_parser(
            "verify"
        )
    )

    verify_parser.add_argument(
        "kind",
        choices=(
            "cpu",
            "gpu",
            "pair",
        ),
    )

    verify_parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
    )

    args = parser.parse_args()

    if args.command == "build":
        if args.kind == "cpu":
            build_cpu(
                args.version,
                args.dist,
            )
        else:
            build_gpu(
                args.version,
                args.dist,
            )

        return

    if args.kind == "cpu":
        if len(args.paths) != 1:
            parser.error(
                "verify cpu requires "
                "exactly one path"
            )

        verify_cpu(
            args.paths[0]
        )
        return

    if args.kind == "gpu":
        if len(args.paths) != 1:
            parser.error(
                "verify gpu requires "
                "exactly one path"
            )

        verify_gpu(
            args.paths[0]
        )
        return

    if len(args.paths) != 2:
        parser.error(
            "verify pair requires "
            "CPU_BUNDLE GPU_ADDON"
        )

    verify_pair(
        args.paths[0],
        args.paths[1],
    )


if __name__ == "__main__":
    main()
