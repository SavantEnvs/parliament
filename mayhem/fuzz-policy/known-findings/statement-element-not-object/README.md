# statement-element-not-object — uncaught JSONConfigNodeTypeError in Statement.analyze_statement

**Reproducer:** `reproducer.json` — `{"Version": "2012-10-17", "Statement": ["Allow"]}`

**Cause.** `Policy.analyze()` (`parliament/policy.py:268-270`) wraps every element of `Statement` in
`Statement(stmt_json)` without checking that the element is a JSON object. `Statement.analyze_statement()`
then iterates it — `for element in self.stmt:` (`parliament/statement.py:671`) — and jsoncfg raises
`JSONConfigNodeTypeError: Expected a ConfigJSONObject or ConfigJSONArray but found ConfigJSONScalar`,
which nothing catches; `analyze_policy_string()` propagates it.

**Impact.** A structurally malformed (but syntactically valid) policy aborts the linter with a traceback
instead of a `MALFORMED` finding: the `parliament` CLI exits with an unhandled exception, and a
`--directory` / `--auth-details-file` scan (or a library caller such as a CI policy gate) stops at that
document, leaving the remaining policies unanalyzed. Denial of service of the linter / lint bypass.

**One-line fix** (`parliament/statement.py`, top of `analyze_statement`, before the `for element in self.stmt` loop):

```python
if not jsoncfg.node_is_object(self.stmt):
    self.add_finding("MALFORMED", detail="Statement is not an object", location=self.stmt); return False
```
