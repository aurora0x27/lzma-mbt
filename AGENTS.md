# AGENTS.md

## 1. Project Mission

This project is an independent implementation of the core functionality of `liblzma` using **MoonBit**.

The primary goals, in order, are:

1. Correctness
2. Behavioral compatibility with the relevant `liblzma` / XZ specification
3. Deterministic and reproducible behavior
4. Testability
5. Maintainability
6. Performance

Do not sacrifice correctness for implementation speed.

The project is developed using an **agent-driven workflow**. Agents must treat this document as the authoritative development protocol.

---

# 2. Core Principles

## 2.1 Specification before implementation

Never implement an algorithm merely because it appears plausible.

For every non-trivial component, identify its governing specification or reference behavior first.

Preferred sources of truth:

1. Official XZ / LZMA specification
2. Existing `liblzma` behavior
3. Formal algorithm descriptions
4. Reference test vectors
5. Existing implementation details
6. Agent assumptions

When sources disagree, explicitly document the discrepancy before choosing an implementation.

Do not silently resolve specification ambiguities.

---

## 2.2 Compatibility is a first-class requirement

This project is not merely "an LZMA compressor written in MoonBit".

Where compatibility is part of the scope, the implementation should reproduce the externally observable behavior of the corresponding `liblzma` functionality.

Compatibility includes, where applicable:

- encoded bitstream format
- decoding behavior
- stream/container format
- error detection
- boundary conditions
- state transitions
- dictionary semantics
- filter semantics
- checksum semantics
- flush behavior
- end-of-stream behavior
- parameter validation
- memory-limit behavior
- incremental input/output behavior

Do not assume that two implementations are compatible merely because they successfully decompress each other's output.

---

# 3. Scope Control

The implementation must be developed incrementally.

Do not attempt to implement the entire `liblzma` API at once.

The preferred implementation order is:

1. Primitive bit/byte utilities
2. Range coder
3. Probability model primitives
4. LZ match finder
5. LZMA state machine
6. LZMA decoder
7. LZMA encoder
8. LZMA2
9. XZ container
10. Checksums
11. Filters
12. Streaming API
13. Public compatibility layer
14. Performance optimization

A component must not be considered complete merely because it compiles.

---

# 4. Repository Architecture

Use a layered architecture.

Recommended conceptual structure:

```text
src/
  bit/
  range_coder/
  lz/
  lzma/
  lzma2/
  filters/
  checksum/
  xz/
  stream/
  api/
  internal/
```

The exact MoonBit package structure may differ, but dependency direction must remain layered.

Lower-level packages must not depend on higher-level container/API packages.

For example:

```text
bit
 ↓
range_coder
 ↓
lzma
 ↓
lzma2
 ↓
xz
 ↓
stream
 ↓
api
```

Do not introduce cyclic dependencies.

---

# 5. Public API vs Internal Implementation

Keep the public API small.

Internal implementation details should not leak into the public API unless there is a strong compatibility reason.

Prefer:

```text
public API
    ↓
stable abstractions
    ↓
algorithm implementation
    ↓
low-level primitives
```

over exposing internal structures directly.

Any API intended to mirror `liblzma` must explicitly document:

- input ownership
- output ownership
- state lifetime
- mutation semantics
- error semantics
- incremental processing semantics
- end-of-stream semantics

---

# 6. Agent Roles

Agents should operate according to explicit roles.

## 6.1 Research Agent

Responsibilities:

- Locate authoritative specifications.
- Analyze existing `liblzma` behavior.
- Extract invariants.
- Produce implementation notes.
- Identify edge cases.
- Create test vectors.

The Research Agent must not modify implementation code unless explicitly assigned to do so.

Output should contain:

```text
Problem
Specification
Relevant invariants
Reference behavior
Edge cases
Test vectors
Open questions
Recommended implementation strategy
```

---

## 6.2 Architecture Agent

Responsibilities:

- Define module boundaries.
- Define data structures.
- Define state machines.
- Review dependency direction.
- Identify abstraction boundaries.

The Architecture Agent should avoid prematurely optimizing algorithms.

---

## 6.3 Implementation Agent

Responsibilities:

- Implement one narrowly scoped component.
- Follow existing architecture.
- Add unit tests.
- Preserve invariants.
- Avoid unrelated refactoring.

An Implementation Agent must not modify unrelated components merely to make its own implementation easier.

If an architectural change is required, stop and document it.

---

## 6.4 Verification Agent

Responsibilities:

- Review implementation against the specification.
- Generate adversarial test cases.
- Compare against reference `liblzma`.
- Check malformed input.
- Check boundary conditions.
- Check state-machine transitions.
- Check streaming behavior.

A Verification Agent should assume that the implementation contains bugs.

"Tests pass" is evidence, not proof.

---

## 6.5 Differential Testing Agent

When applicable, compare MoonBit behavior against the reference implementation.

For each test case:

```text
input
parameters
reference output / behavior
MoonBit output / behavior
comparison
```

For deterministic formats, compare exact bytes when appropriate.

For semantically equivalent but non-deterministic output, compare decoded semantics instead.

---

## 6.6 Performance Agent

Performance work is allowed only after correctness is established.

Measure before optimizing.

Every optimization must preserve:

- observable behavior
- test coverage
- memory safety
- streaming semantics
- deterministic behavior where required

Record benchmark results before and after optimization.

---

## 6.7 Review Agent

The Review Agent performs final review before a task is marked complete.

Review dimensions:

```text
Specification compliance
Algorithmic correctness
Boundary conditions
Error handling
API semantics
Tests
Performance regressions
Code complexity
Unnecessary duplication
Documentation
```

---

# 7. Task Protocol

Every agent task must have a clear scope.

A task should look conceptually like:

```text
Task:
Implement LZMA range decoder.

Prerequisites:
- range coder research completed
- bit reader available

Inputs:
- relevant specification
- existing package interfaces

Expected outputs:
- implementation
- unit tests
- reference vectors
- implementation notes

Acceptance criteria:
- all existing tests pass
- new vectors pass
- malformed input is rejected correctly
- no unrelated API changes
```

Agents must not expand task scope silently.

If implementation reveals a missing prerequisite, create a follow-up task instead of inventing an undocumented architecture.

---

# 8. Definition of Done

A task is complete only when all applicable conditions are satisfied.

## Required

- Code compiles.
- Unit tests pass.
- Existing tests remain green.
- New behavior has tests.
- Edge cases are covered.
- Public behavior is documented.
- No known correctness issue remains.

## For algorithmic components

Additionally:

- Specification has been identified.
- Core invariants are documented.
- Reference vectors exist.
- Differential tests exist when possible.

## For compatibility components

Additionally:

- Behavior has been compared with the reference implementation.
- Error behavior has been checked.
- Streaming behavior has been checked.
- Boundary behavior has been checked.

---

# 9. Testing Strategy

Testing must be layered.

## 9.1 Unit tests

Test individual primitives:

- bit operations
- byte operations
- probability updates
- range coder
- state transitions
- match distances
- dictionary operations
- checksums

---

## 9.2 Property tests

Where practical, test properties such as:

```text
decode(encode(x)) == x
```

for valid inputs.

Also test:

```text
encode/decode preserves arbitrary byte sequences
```

including:

- empty input
- one-byte input
- highly repetitive data
- random data
- incompressible data
- very long runs
- repeated patterns
- boundary-sized dictionaries

---

## 9.3 Differential tests

Compare against the reference implementation whenever possible.

At minimum:

```text
MoonBit encoder → reference decoder
reference encoder → MoonBit decoder
```

For container formats:

```text
MoonBit output → reference tool
reference output → MoonBit decoder
```

Do not rely exclusively on round-trip tests performed entirely within the MoonBit implementation.

An encoder and decoder can share the same bug.

---

## 9.4 Negative tests

Malformed data is part of the input domain.

Test:

- truncated streams
- invalid headers
- invalid properties
- invalid distances
- invalid lengths
- invalid checksums
- invalid filter chains
- impossible state transitions
- excessive dictionary sizes
- unexpected end of input
- corrupted compressed data

The implementation must fail predictably rather than panic.

---

# 10. Reference Implementation

The reference `liblzma` implementation should be treated as an **oracle for behavior**, not as code to blindly translate.

Do not perform mechanical line-by-line ports.

Instead:

```text
reference implementation
        ↓
understand algorithm
        ↓
extract invariants
        ↓
design MoonBit representation
        ↓
implement independently
        ↓
differential test
```

When behavior is copied from an implementation rather than from a specification, explicitly record why.

---

# 11. Porting Rules

This is an implementation in MoonBit, not a C-to-MoonBit transliteration.

Do not preserve C implementation patterns merely because they exist in `liblzma`.

Avoid blindly translating:

- pointer arithmetic
- manual memory management
- macros
- unions
- sentinel values
- implicit integer conversions
- mutable global state
- error-code conventions that do not fit the MoonBit API

Instead, preserve the underlying invariant and behavior.

For each translated algorithm, identify:

```text
C representation
Algorithmic meaning
MoonBit representation
Invariant preserved
```

---

# 12. Integer and Bit-Level Correctness

Bit-level code must be treated as high-risk code.

For operations involving:

- shifts
- masks
- rotations
- integer overflow
- signed/unsigned conversion
- byte order
- bit packing
- bit extraction

explicitly reason about the integer domain.

Do not assume that a C expression and its MoonBit equivalent have identical semantics.

Whenever integer behavior is important, add focused tests.

---

# 13. State Machines

LZMA, LZMA2, streaming, and XZ processing contain stateful behavior.

Represent state explicitly.

Prefer:

```text
state + transition
```

over hidden mutation spread across unrelated functions.

For every state machine, document:

```text
States
Inputs/events
Transitions
Outputs
Invalid transitions
Terminal states
Reset semantics
```

Tests must cover every meaningful transition.

---

# 14. Error Handling

Errors must be explicit.

Do not use:

```text
panic
assert
undefined behavior
silent recovery
```

as normal malformed-input handling.

Distinguish, where applicable:

```text
Invalid input
Unexpected end of input
Invalid configuration
Unsupported feature
Resource limit
Internal invariant violation
```

Internal invariant violations may justify assertions, but externally supplied compressed data must never be trusted.

---

# 15. Streaming Semantics

Streaming is a first-class concern.

Do not implement a whole-buffer API first and assume it automatically provides correct streaming semantics.

Explicitly test:

```text
all input at once
one byte at a time
small chunks
random chunk sizes
input ending at every possible state
output buffer exhaustion
repeated flush
end-of-stream
```

A streaming decoder must produce correct results regardless of how valid input is partitioned into chunks.

---

# 16. Memory and Resource Limits

Compressed input is untrusted input.

Agents must consider:

- dictionary allocation
- decompression expansion
- malformed distance values
- excessive memory requirements
- pathological match lengths
- extremely large streams
- integer overflow
- resource exhaustion

Never remove validation merely because valid inputs do not require it.

---

# 17. Security

Security is part of correctness.

For every parser or decoder, consider:

```text
memory exhaustion
CPU exhaustion
integer overflow
out-of-bounds access
invalid state transitions
crafted malformed streams
decompression bombs
```

Do not optimize away validation without measurement and justification.

---

# 18. Documentation Requirements

Non-obvious algorithms must contain comments explaining **why**, not merely **what**.

Bad:

```text
// increment position
pos += 1
```

Good:

```text
// The decoder advances the position only after the full match
// has been validated, because distance validation depends on
// the current dictionary boundary.
```

Document invariants close to the code that relies on them.

---

# 19. Commit / Change Discipline

Keep changes small and conceptually atomic.

Prefer:

```text
implement range decoder
add range decoder vectors
fix range decoder boundary case
```

over:

```text
implement everything
refactor architecture
optimize performance
rename APIs
```

in a single change.

Do not mix correctness fixes with unrelated refactoring.

---

# 20. Agent Handoff Protocol

An agent handing work to another agent must provide:

```text
## Completed

...

## Changed

...

## Verified

...

## Known limitations

...

## Open questions

...

## Suggested next task

...
```

The next agent must not assume undocumented behavior.

---

# 21. Agent Stop Conditions

An agent must stop and request clarification or create a follow-up task when:

1. The specification is ambiguous.
2. Two reference behaviors conflict.
3. An API decision affects multiple layers.
4. A change requires modifying unrelated components.
5. A test exposes a deeper architectural problem.
6. Correctness cannot be established from available evidence.
7. The requested implementation would require guessing.

Do not "resolve" architectural uncertainty by silently choosing an arbitrary behavior.

---

# 22. Forbidden Agent Behaviors

Agents must not:

- Rewrite large portions of the repository without a task.
- Remove failing tests merely to make CI pass.
- Weaken validation to accommodate a test.
- Copy large amounts of reference C code without understanding it.
- Claim compatibility without differential testing.
- Mark a component complete because it compiles.
- Add speculative abstractions without a concrete use case.
- Optimize code without benchmarks.
- Change public APIs without an explicit task.
- Hide known correctness issues.
- Ignore malformed-input behavior.
- Treat successful round-trip tests as sufficient evidence of correctness.

---

# 23. Research Notes

Every major algorithm should have a corresponding research note.

Recommended format:

```text
docs/research/<component>.md
```

Each note should contain:

```text
# Component

## Scope

## Specification

## Reference implementation

## Data model

## Algorithm

## Invariants

## Edge cases

## Error cases

## Test vectors

## Compatibility notes

## Open questions
```

---

# 24. Recommended Development Pipeline

The default pipeline is:

```text
Research
   ↓
Specification extraction
   ↓
Architecture
   ↓
Minimal implementation
   ↓
Unit tests
   ↓
Reference vectors
   ↓
Differential testing
   ↓
Negative testing
   ↓
Code review
   ↓
Benchmarking
   ↓
Optimization
```

Do not skip directly from:

```text
"we understand the algorithm"
```

to:

```text
"implementation complete"
```

---

# 25. Milestones

The project should use explicit milestones.

## M0 — Infrastructure

- MoonBit project structure
- CI
- test infrastructure
- differential test harness
- reference `liblzma` test harness

## M1 — Primitive Coding

- bit reader/writer
- byte reader/writer
- integer helpers
- checksum primitives

## M2 — Range Coder

- range encoder
- range decoder
- probability model
- reference vectors

## M3 — LZMA Decoder

- decoder state
- dictionary
- literal decoding
- match decoding
- distance decoding
- end marker
- malformed stream handling

## M4 — LZMA Encoder

- match finder
- optimal parsing
- encoder state
- probability updates
- parameter handling

## M5 — LZMA2

- chunk structure
- state reset semantics
- dictionary handling
- compressed/uncompressed chunks

## M6 — XZ

- stream header
- block structure
- index
- footer
- checksums
- filter chain

## M7 — Filters

Implement supported filters incrementally and independently.

## M8 — Streaming API

- incremental decoding
- incremental encoding
- flush
- end-of-stream
- buffer exhaustion

## M9 — Compatibility Layer

Only after the underlying implementation is stable.

## M10 — Performance

Benchmark first, optimize second.

---

# 26. Compatibility Matrix

Maintain a machine-readable or documented compatibility matrix.

Example:

| Feature | Decoder | Encoder | Streaming | Differential Tested |
| ------- | ------: | ------: | --------: | ------------------: |
| LZMA1   |  yes/no |  yes/no |    yes/no |              yes/no |
| LZMA2   |  yes/no |  yes/no |    yes/no |              yes/no |
| XZ      |  yes/no |  yes/no |    yes/no |              yes/no |
| CRC32   |  yes/no |  yes/no |       N/A |              yes/no |
| CRC64   |  yes/no |  yes/no |       N/A |              yes/no |
| BCJ     |  yes/no |  yes/no |    yes/no |              yes/no |

Never mark a feature as complete without corresponding evidence.

---

# 27. Final Rule

When uncertain:

**Do not guess.**

Instead:

```text
identify uncertainty
    ↓
find specification
    ↓
inspect reference behavior
    ↓
create minimal reproducer
    ↓
write test
    ↓
implement
    ↓
verify
```

The goal is not to make an agent produce code as quickly as possible.

The goal is to make a sequence of agents converge reliably toward a correct, testable, maintainable, and compatible implementation.
