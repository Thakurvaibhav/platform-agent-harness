# Skill: Systematic Debugging

> 4-phase root cause investigation protocol. Prevents blind retry loops by enforcing evidence gathering, hypothesis formation, isolated testing, and defense-in-depth fixes.

---

## When to use

- Any error where the first fix attempt failed
- Build/test failures that aren't obvious syntax or import errors
- Gate failures after first retry
- Any time you're about to retry the same thing hoping for a different result

## When NOT to use

- Obvious syntax errors (missing comma, typo)
- Import errors with clear messages
- Type errors with explicit expected/actual

---

## The 4 phases

### Phase 1: Gather evidence (DO NOT SKIP)

Before forming any hypothesis, collect ALL available evidence.

```
EVIDENCE CHECKLIST:
[ ] Exact error message (full text, not summary)
[ ] Full stack trace (if available)
[ ] Which command/test/gate produced the error
[ ] What changed since the last working state (git diff)
[ ] Environment state (versions, config)
[ ] Reproduction steps (reliable or intermittent?)
[ ] Related log output (not just the error line)
[ ] Recent changes to files in the error's dependency chain
```

**Rule:** Produce at least 3 pieces of evidence before proceeding. If you have fewer than 3, you haven't looked hard enough.

---

### Phase 2: Form hypotheses (exactly 3, ranked)

From the evidence, generate 3 hypotheses. Not 1 (tunnel vision). Not 10 (unfocused).

```
HYPOTHESIS TABLE:
| # | Hypothesis | Evidence For | Evidence Against | Likelihood | How to Test |
|---|-----------|-------------|-----------------|------------|-------------|
| H1 | [Most likely] | | | High | |
| H2 | [Second likely] | | | Medium | |
| H3 | [Less likely but possible] | | | Low | |
```

**Quality rules:**
- Each hypothesis must explain ALL symptoms, not just some
- Each must have a testable prediction
- "The code is wrong" is not a hypothesis -- be specific
- If all 3 point to the same area, think broader: data issue? timing? config? dependency?

---

### Phase 3: Test hypotheses (in order, stop when confirmed)

For each hypothesis:
1. Define the test that would confirm or reject it
2. Execute the test (minimal, isolated -- don't change production code yet)
3. Record CONFIRMED or REJECTED with evidence
4. If rejected, move to next

**Techniques:**

| Technique | When | How |
|-----------|------|-----|
| Minimal reproduction | Complex failures | Smallest case that still fails |
| Bisection | "It worked before" | git bisect or manual binary search |
| Component isolation | Multi-service errors | Test each component independently |
| Input variation | Data-dependent | Try different inputs to isolate trigger |
| Log injection | Black-box failures | Add temporary logging at each step |

---

### Phase 4: Fix and verify (defense in depth)

Once root cause is confirmed:

1. **Fix the root cause** -- not the symptom
2. **Add a regression test** -- fails without fix, passes with fix
3. **Check for similar patterns** -- does this bug exist in similar code elsewhere?
4. **Verify the fix** -- run the originally failing command
5. **Check for regressions** -- run the full test suite
6. **Document the root cause** -- persist as a learning

```
FIX VERIFICATION:
[ ] Root cause fix applied (not a workaround)
[ ] Regression test added
[ ] Similar code checked for same pattern
[ ] Originally failing test/gate passes
[ ] Full test suite passes (no regressions)
[ ] Fix does not modify test expectations (unless tests were wrong)
```

---

## Output format

Every debugging session produces this summary:

```yaml
debugging_report:
  symptom: "1-line description"
  evidence_count: N
  hypotheses:
    - id: H1
      description: "..."
      result: "confirmed | rejected"
    - id: H2
      description: "..."
      result: "confirmed | rejected"
    - id: H3
      description: "..."
      result: "confirmed | rejected | not_tested"
  root_cause:
    confirmed_hypothesis: "H1 | H2 | H3 | none"
    description: "what actually caused the failure"
    category: "logic_error | data_issue | config_error | race_condition | dependency_change | schema_mismatch | missing_validation"
  fix:
    changes: ["file paths"]
    regression_test_added: true | false
    similar_patterns_checked: true | false
  learning: "what to remember for next time"
```

After completing the report, persist the learning:
```
bd remember "<root cause and fix summary>" --key <repo>/trouble/<topic>
```

---

## Anti-patterns

| Anti-Pattern | Do This Instead |
|-------------|-----------------|
| Fix without evidence | Phase 1 first. Always. |
| Single hypothesis | 3 hypotheses minimum |
| Modify tests to pass | Tests are the spec. Fix the code. |
| Retry without understanding | Systematic debugging between retries |
| "It works now" without knowing why | Root cause must be identified |
| Quick patch on symptom | Root cause + regression test + similar pattern check |
| Changing multiple things at once | One change at a time. Test after each. |
