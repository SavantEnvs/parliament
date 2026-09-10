# fuzz-policy — known findings (reproducers, NOT seeds)

Each subdirectory holds a minimized reproducer for a distinct crash the `fuzz-policy` harness
found on this checkout (duo-labs/parliament @ 574ea45), plus a README with cause, impact and the
one-line upstream fix. They live here and NOT in `../testsuite/` on purpose: seeds are replayed on
every Mayhem run and must all pass.

All three share one root cause: parliament walks the policy JSON through `jsoncfg` node objects and
assumes the *shape* of each element (object / array / scalar) without checking it, so a policy that
is valid JSON but structurally malformed raises `jsoncfg.config_classes.JSONConfigNodeTypeError`
out of `analyze_policy_string()` instead of producing a `MALFORMED` finding.

Reproduce (in the commit image):

    /mayhem/fuzz-policy -runs=1 mayhem/fuzz-policy/known-findings/<slug>/reproducer.json   # exit 77, Python traceback
    /mayhem/parliament-cli --files mayhem/fuzz-policy/known-findings/<slug>/reproducer.json  # CLI traceback, exit 1

| slug | crash site | trigger |
| --- | --- | --- |
| `statement-element-not-object` | `parliament/statement.py:671` `for element in self.stmt` | a `Statement` list element that is a scalar |
| `effect-not-scalar` | `parliament/statement.py:720` `effect.value` | `Effect` that is an array/object |
| `condition-block-not-object` | `parliament/statement.py:533` `for block in condition_block` | a `Condition` operator whose block is a scalar |
