# Skill: Stop Slop (Code Mode)

> Detects structural code problems that indicate incomplete, lazy, or AI-generated code. Run during code review or before PR creation.

---

## When to use

- Before creating a PR (as part of review)
- When reviewing code produced by any sub-agent
- When auditing code quality of generated changes

---

## Detection patterns

### 1. Placeholder detection (hard failure)

Any match is immediate fix required -- no scoring, no exceptions.

```
pass\s*(#.*)?$              # bare pass statements (Python)
TODO\b                      # TODO comments
FIXME\b                     # FIXME comments
raise NotImplementedError   # Python stubs
\.\.\.\s*$                  # ellipsis as function body
throw new Error\("not implemented"\)  # JS/TS stubs
```

Also flag:
- Function body is empty `{}`
- Function body is a single `pass` or ellipsis
- Class body is a single `pass` with no docstring

### 2. God function detection (warning at 50 SLOC, failure at 100)

Count non-blank, non-comment, non-decorator lines inside the function body.

- **> 50 SLOC**: Warning -- consider decomposing
- **> 100 SLOC**: Hard failure -- must decompose before merge

### 3. Near-duplicate code blocks

Flag any two code blocks (3+ lines) with high similarity within the same file or across files in the same diff.

- **> 80% token similarity**: Warning -- extract shared utility
- **> 95% similarity**: Hard failure -- copy-paste detected, must refactor

### 4. Identity transforms

Comprehensions that return the loop variable unchanged:

```python
# Flagged:
[x for x in items]
{k: v for k, v in d.items()}

# Not flagged (these transform):
[x.name for x in items]
[x for x in items if x.active]
```

### 5. Unnecessary defensive comparisons

```python
# Flagged -> Fix
if x == True:        ->  if x:
if x == False:       ->  if not x:
if x == None:        ->  if x is None:
if len(items) > 0:   ->  if items:
if bool(x):          ->  if x:
```

### 6. Hardcoded values outside config

Flag URLs, ports, timeouts, and sleep values in production code:

```
https?://[^\s"']+            # URLs
:\d{4,5}[/"'\s]             # port numbers
timeout\s*=\s*\d+           # hardcoded timeouts
sleep\(\s*\d+               # hardcoded sleep values
```

**Exempt:** files in `**/config/**`, `**/.env*`, `**/test*/**`, `**/fixture*/**`, `**/mock*/**`.

### 7. Missing test coverage for new functions

For any new function added in a diff, check that a corresponding test exists:
- `test_<function_name>` in test files
- `<function_name>.test.ts` or `<function_name>.spec.ts`
- `describe("<FunctionName>"` block

Missing test for new public function = warning. Missing test file entirely = hard failure.

---

## Scoring

Hard failures block delivery. Warnings accumulate:
- **0 warnings**: Clean
- **1-3 warnings**: Proceed with notice
- **4+ warnings**: Block until addressed

---

## Review output format

```
SLOP CHECK REPORT:
| Placeholders:          PASS / FAIL (N found)
| God functions:         PASS / WARN / FAIL (list with SLOC counts)
| Near-duplicates:       PASS / WARN / FAIL (file pairs + similarity %)
| Identity transforms:   PASS / FAIL (N found)
| Defensive comparisons: PASS / FAIL (N found)
| Hardcoded values:      PASS / WARN (N found, list files)
| Missing tests:         PASS / WARN / FAIL (new functions without tests)
| ---
| Hard failures:         N
| Warnings:              N
| Verdict:               CLEAN / WARN / BLOCKED
```

---

## Integration

This skill is referenced during code review. When reviewing a diff:

1. Scan changed files against all detection patterns above
2. Produce the slop check report
3. Include findings in review comments with specific file + line references
4. Hard failures must be resolved before approval

This does NOT replace functional review -- it catches structural problems that functional review misses.
