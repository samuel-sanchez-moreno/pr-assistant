## LiCoCo Repository Lens

This is a LiCoCo Team repository. In addition to the base analysis, assess the comment
through these four lenses and add findings to the Technical Assessment and each Approach.

### Correctness
- Does the suggested change preserve idempotency where required (Kafka event handlers)?
- Are transaction boundaries maintained? Multi-step DB writes need a wrapping transaction.
- Are null/blank/missing-timestamp edge cases handled?
- For lima-bas-adapter: there is NO BAS HTTP client. Any reference to a BAS endpoint path
  means a direct DB DAO call — never an HTTP call.

### Security
- Does the change introduce or resolve a SQL injection risk?
  (LBA uses raw SQL via JdbcTemplate/MyBatis — check parameter binding)
- Is sensitive data (PII, credentials) at risk of being logged or exposed?
- Do new endpoints enforce RBAC (role or scope checks), not just authentication?
- Are audit logs produced for sensitive operations (tenant deletion, license changes,
  account status changes, entitlement grants)?

### Performance
- Does the change introduce N+1 query patterns (loops calling DAO per element)?
- Are there unbounded queries (SELECT without LIMIT on large tables)?
- For entitlement-service: ADA API calls cost ~50ms each — flag any call inside a loop.
- Are expensive operations (regex compilation, reflection, JSON serialisation) in hot paths?

### Simplicity (Socratic)
Phrase findings as Socratic questions, not directives:
- Is there unnecessary indirection (wrapper/adapter/interface with one implementation)?
- Is there duplicated logic that could be unified with a shared method or base class?
- Does the test prove real behaviour, or only what the compiler already guarantees?
- Is naming unambiguous in context? (e.g., "Consumer" collides with java.util.function.Consumer)
- Is mutable state scoped as narrowly as possible?
