#!/usr/bin/env python3
"""Decode this library's encoder output with liblzma / xz.

The MoonBit package `src/cmd/diff_encode` emits named cases on stdout.
This script is the encode-side oracle: plaintext after reference decode
must match the payload. Encoder bytes are not required to match `xz -6`.
"""

from __future__ import annotations

import argparse
import lzma
import shutil
import subprocess
import sys
from pathlib import Path

REQUIRED_CASES = {
    "empty_xz_p6_crc64",
    "empty_lzma_p6",
    "empty_lzma2_p6",
    "empty_xz_p6_crc32",
    "empty_xz_p6_none",
    "short_xz_p6_crc64",
    "short_lzma_p6",
    "short_lzma2_p6",
    "short_xz_p0_crc64",
    "short_lzma_p0",
    "short_lzma2_p0",
    "short_xz_p6_crc32",
    "short_xz_p6_none",
    "run64_xz_p6_crc64",
    "run64_lzma_p6",
    "run64_lzma2_p6",
    "incomp256_xz_p6_crc64",
    "incomp256_lzma_p6",
    "incomp256_lzma2_p6",
    "over64k_xz_p6_crc64",
    "over64k_lzma_p6",
    "over64k_lzma2_p6",
    "over64k_xz_p0_crc64",
    "incomp64k_lzma2_p6",
    "incomp64k_xz_p6_crc64",
    "incomp64k_lzma_p6",
}

REPO_ROOT = Path(__file__).resolve().parent.parent


def parse_cases(text: str) -> list[dict[str, str]]:
    if "ERROR " in text:
        raise RuntimeError(f"encoder dump failed:\n{text.strip()[-500:]}")
    if "LZMA_MBT_DIFF_V1" not in text:
        raise RuntimeError("missing LZMA_MBT_DIFF_V1 banner from encoder dump")
    if "\nDONE" not in text and not text.rstrip().endswith("DONE"):
        raise RuntimeError("encoder dump did not finish (missing DONE)")

    cases: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("CASE "):
            if current is not None:
                raise RuntimeError(f"case {current.get('name')} missing END")
            current = {"name": line[5:]}
        elif line == "END":
            if current is None:
                raise RuntimeError("END without CASE")
            for key in (
                "format",
                "preset",
                "check",
                "dict",
                "plain_len",
                "plain_hex",
                "comp_hex",
            ):
                if key not in current:
                    raise RuntimeError(f"case {current.get('name')} missing {key}")
            cases.append(current)
            current = None
        elif current is not None and "=" in line:
            key, value = line.split("=", 1)
            current[key] = value
        elif line in {"LZMA_MBT_DIFF_V1", "DONE"} or line.startswith("Finished."):
            continue
        elif line:
            # moon / runtime noise on stdout is unexpected once a case is open
            if current is not None:
                raise RuntimeError(f"unexpected dump line: {line!r}")
    if current is not None:
        raise RuntimeError(f"case {current.get('name')} missing END")
    return cases


def decode_liblzma(fmt: str, data: bytes, dict_size: int) -> bytes:
    if fmt == "xz":
        return lzma.decompress(data, format=lzma.FORMAT_XZ)
    if fmt == "lzma":
        return lzma.decompress(data, format=lzma.FORMAT_ALONE)
    if fmt == "lzma2":
        return lzma.decompress(
            data,
            format=lzma.FORMAT_RAW,
            filters=[{"id": lzma.FILTER_LZMA2, "dict_size": dict_size}],
        )
    raise ValueError(f"unsupported format {fmt}")


def decode_xz_cli(xz: str, fmt: str, data: bytes, dict_size: int) -> bytes:
    cmd = [xz, "-d", "--stdout"]
    if fmt == "xz":
        cmd.append("--format=xz")
    elif fmt == "lzma":
        cmd.append("--format=lzma")
    elif fmt == "lzma2":
        cmd.extend(["--format=raw", f"--lzma2=dict={dict_size}"])
    else:
        raise ValueError(f"unsupported format {fmt}")
    proc = subprocess.run(cmd, input=data, capture_output=True, check=False)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace")
        raise RuntimeError(f"xz -d failed (exit {proc.returncode}): {err}")
    return proc.stdout


def dump_cases(moon: str, target: str, timeout: int) -> str:
    proc = subprocess.run(
        [moon, "run", "--target", target, "-q", "src/cmd/diff_encode"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "moon run failed "
            f"(exit {proc.returncode})\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default="wasm-gc")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--skip-xz", action="store_true")
    args = parser.parse_args()

    moon = shutil.which("moon")
    if moon is None:
        print("moon is not on PATH", file=sys.stderr)
        return 1

    print(f"dumping encoder cases via {moon} --target {args.target}", flush=True)
    text = dump_cases(moon, args.target, args.timeout)
    cases = parse_cases(text)
    names = {c["name"] for c in cases}
    missing = REQUIRED_CASES - names
    if missing:
        print(f"missing required cases: {sorted(missing)}", file=sys.stderr)
        return 1

    xz = None if args.skip_xz else shutil.which("xz")
    if xz is None and not args.skip_xz:
        print("xz not on PATH; liblzma (Python lzma) only", flush=True)

    failed = 0
    for case in cases:
        name = case["name"]
        fmt = case["format"]
        dict_size = int(case["dict"])
        plain = bytes.fromhex(case["plain_hex"]) if case["plain_hex"] else b""
        comp = bytes.fromhex(case["comp_hex"]) if case["comp_hex"] else b""
        if len(plain) != int(case["plain_len"]):
            print(f"FAIL {name}: plain_len mismatch", file=sys.stderr)
            failed += 1
            continue
        try:
            got = decode_liblzma(fmt, comp, dict_size)
        except Exception as exc:  # noqa: BLE001 — oracle must report any decode error
            print(f"FAIL {name}: liblzma {exc}", file=sys.stderr)
            failed += 1
            continue
        if got != plain:
            print(
                f"FAIL {name}: liblzma plaintext mismatch "
                f"(got {len(got)} bytes, want {len(plain)})",
                file=sys.stderr,
            )
            failed += 1
            continue
        if xz is not None:
            try:
                got_xz = decode_xz_cli(xz, fmt, comp, dict_size)
            except Exception as exc:  # noqa: BLE001
                print(f"FAIL {name}: xz -d {exc}", file=sys.stderr)
                failed += 1
                continue
            if got_xz != plain:
                print(
                    f"FAIL {name}: xz -d plaintext mismatch "
                    f"(got {len(got_xz)} bytes, want {len(plain)})",
                    file=sys.stderr,
                )
                failed += 1
                continue
        extra = f", xz={xz}" if xz else ""
        print(f"ok {name} ({fmt}, {len(plain)} bytes{extra})", flush=True)

    if failed:
        print(f"{failed} case(s) failed", file=sys.stderr)
        return 1
    print(f"{len(cases)} case(s) passed (liblzma" + (f" + xz" if xz else "") + ")")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
