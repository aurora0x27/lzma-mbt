# Toolchain requirement (mandatory)

## Scope

This note records the MoonBit toolchain version that the repository is written
against. It is a project requirement, not a suggestion: code and the completion
gates in `task.md` assume this toolchain.

## Requirement

The mandatory toolchain is the one installed on the development machine:

```text
moon  0.1.20260904  (built-in core 0.10.12+1634b282e)
```

The matching distribution identifier is pinned at the repository root in the
`moonbit-version` file (honoured by moonup) and used by CI via
`chawyehsu/setup-moonup@v1` `moonbit-version`:

```text
0.10.12+1634b282e
```

A task must be developed and verified with this version. If a machine has a
different MoonBit version, do **not** silently adapt: either use the mandated
version or stop and report the mismatch.

## Why this version

`moon 0.1.20260904` bundles core `0.10.12`, which deprecates
`Array::new(capacity=...)` in favor of the `Array(capacity=...)` constructor
(upstream core change "add Array::Array constructor, deprecate Array::new",
merged 2026-09-01). The repository therefore uses only the non-deprecated
`Array(capacity=...)` / `Array()` forms.

- Older toolchains whose core predates 2026-09-01 may not provide the
  `Array(...)` constructor, so the migrated code is **not** expected to build
  on them. Treat `0.1.20260904` as the minimum and only supported version.
- Never "fix" CI or a task by weakening `--deny-warn`; the repository compiles
  warning-free on the mandated toolchain, and the gates below are the contract.

## Gates

All must pass on the mandated toolchain:

```text
moon check --deny-warn
moon fmt --check
moon test --deny-warn
python3 scripts/diff_encode.py
```

## History

- 2026-09: repository migrated every `Array::new(capacity=...)` /
  `Array::new()` call site to `Array(capacity=...)` / `Array()` so the
  pre-existing tree passes `--deny-warn` on `0.1.20260904` (CI had been red
  under the newer core's deprecation). Migration is behavior-neutral.
- 2026-09: after a rebase that kept an earlier "complete T4" overlay on top of
  the T7d base, `src/xz/xz.mbt` no longer compiled (the overlay half-applied a
  reader-based `decode_xz` and corrupted `parse_index_and_footer` variable
  names) and `src/api_test.mbt` gained unused helpers. The T7d base already
  implements concatenated `.xz` decode, so the fix restored those files to the
  T7d content; this note, its index rows and the `README.md` build note are the
  only additions that remain relative to T7d.
- 2026-09: CI switched from the non-existent `moonbitlang/setup-moonbit@v1` to
  `chawyehsu/setup-moonup@v1`, pinning the distribution identifier (same value
  as the committed `moonbit-version` file).

## Open questions

None.
