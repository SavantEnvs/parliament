# effect-not-scalar — uncaught JSONConfigNodeTypeError on a non-scalar `Effect`

**Reproducer:** `reproducer.json` — `{"Version": "2012-10-17", "Statement": {"Effect": [], "Action": "s3:GetObject", "Resource": "*"}}`

**Cause.** `Statement.analyze_statement()` checks that `Effect` exists, then reads
`effect.value` (`parliament/statement.py:720`, `if effect.value not in ["Allow", "Deny"]:`) assuming the
node is a scalar. For an array (or object) node jsoncfg's `__getattr__` raises
`JSONConfigNodeTypeError: Expected a ConfigJSONObject but found ConfigJSONArray ... item=value`,
which nothing catches; `analyze_policy_string()` propagates it.

**Impact.** Same as the other findings in this directory: a syntactically valid policy with a wrong-typed
element crashes the linter (CLI traceback, library exception) instead of yielding the `MALFORMED`
finding the very next line intends to report — a linter DoS / lint bypass for the rest of a scan.

**One-line fix** (`parliament/statement.py:720`):

```python
if not jsoncfg.node_is_scalar(effect) or effect.value not in ["Allow", "Deny"]:
```
