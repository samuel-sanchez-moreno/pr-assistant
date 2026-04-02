## Debugging Lens

This comment references a bug, failure, regression, or exception. Apply the systematic
debugging protocol before proposing any fix.

### Before Proposing a Fix

1. **Reproduce first.** Do not propose a fix without confirming the issue exists in the
   current codebase. Describe how you would reproduce it.

2. **Trace the root cause.** Where does the bad value or behavior originate?
   Trace backward through the call stack to the actual source — not the symptom.

3. **Check recent changes.** What changed that could have introduced this? Look at git
   history, new dependencies, config changes.

4. **Verify the reviewer's diagnosis.** Is the reviewer's identified root cause correct?
   They may have spotted the symptom but misidentified the cause.

### Output Additions

Add a **Root Cause Analysis** section to your output, before the Approaches:

### Root Cause Analysis
- How to reproduce the issue
- Where in the call stack the failure originates
- Whether the reviewer's diagnosis is correct or incomplete
- What the actual fix target is (may differ from the anchor location)

### Approach Constraints
- Approach 1 (Comply) must fix the root cause, not just mask the symptom.
- Approach 3 (Reasoned Alternative) is only valid if the reviewer's diagnosis is wrong
  AND you can prove the actual root cause is elsewhere.
- Do NOT propose a fix that passes the test but leaves the underlying cause in place.
