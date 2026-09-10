# condition-block-not-object — uncaught JSONConfigNodeTypeError in Statement._check_condition

**Reproducer:** `reproducer.json` — `{"Version": "2012-10-17", "Statement": {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*", "Condition": {"StringEquals": "x"}}}`

**Cause.** `Statement._check_condition(operator, condition_block)` receives the value of each
`Condition` operator and iterates it as a mapping of condition keys — `for block in condition_block:`
(`parliament/statement.py:533`; the `Bool` branch a few lines earlier does the same) — without checking
that the block is a JSON object. For a scalar block jsoncfg raises
`JSONConfigNodeTypeError: Expected a ConfigJSONObject or ConfigJSONArray but found ConfigJSONScalar`,
which nothing catches; `analyze_policy_string()` propagates it.

**Impact.** Same class as the other findings here: valid JSON with a wrong-typed `Condition` block crashes
the linter (CLI traceback, unhandled exception for library callers) instead of a `MALFORMED` /
`UNKNOWN_CONDITION_FOR_ACTION` finding — a linter DoS / lint bypass for the rest of a scan.

**One-line fix** (`parliament/statement.py`, start of `_check_condition`):

```python
if not jsoncfg.node_is_object(condition_block):
    self.add_finding("MALFORMED", detail="Condition block is not an object", location=condition_block); return False
```
