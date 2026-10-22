# GitHub Copilot Coding Standard & SDLC Rules

## Core Principles
1. **Source of Truth**: The local SDLC pipeline executed via `.\tools\sdlc.ps1` is the absolute authority on code quality. Never claim code is correct without pipeline verification.
2. **Self-Correction Loop**: When `sdlc-report.json` indicates `FAILED`, inspect the `errors` array and `metrics` section, fix the exact failures, and re-run the pipeline.
3. **Agent Delegation**: Use specialized agents for distinct tasks:
   - `@sdlc-orchestrator` — end-to-end delivery; drives the agents below until the pipeline is green
   - `@planner` — architecture & task decomposition (outputs `plan.md`)
   - `@developer` — code implementation following `plan.md`
   - `@test-engineer` — test creation following the testing pyramid
   - `@security-reviewer` — security audit (outputs `security-review.md`)
   - `@quality-fixer` — automated fix loop based on `sdlc-report.json`

## SDLC Workflow
```
Requirement → @sdlc-orchestrator
   → @planner → plan.md → @developer → code → @test-engineer → tests
   → @security-reviewer → security-review.md
   → .\tools\sdlc.ps1 → sdlc-report.json → PASS? → DONE
                                           → FAIL? → @quality-fixer → re-run
```

## Code Standards
- **Java Version**: Java 25 features (records, pattern matching, sealed classes) preferred.
- **Spring Boot 4.x**: Follow standard 3-tier architecture (Controller → Service → Repository).
- **Packages**: Package by feature, not by layer — `com.example.app.customer` holds `Customer`, `CustomerRepository`, `CustomerService`, `CustomerController`, `CustomerDto`. Cross-cutting code (`exception`, `config`) gets its own package.
- **Validation**: Always annotate DTOs with `@Valid` and JSR-380 constraints (`@NotNull`, `@Size`, `@Email`).
- **Injection**: Constructor injection only. No `@Autowired` on fields.
- **Persistence**: Spring Data (MongoDB or JPA/PostgreSQL/DB2 depending on configuration). Repositories extend `MongoRepository` or `JpaRepository`/`CrudRepository`. Never build queries by concatenating user input — use derived query methods or parameterized queries.
- **Testing**: Use `@WebMvcTest` for API endpoints, `@DataMongoTest` or `@DataJpaTest` for repositories, `@SpringBootTest` for integration tests. Use AssertJ and Mockito.
- **Coverage**: Minimum 60% line coverage enforced by JaCoCo. Aim for 80%+ on service layer.

## Quality Gates (enforced by `sdlc.ps1`)
1. **Compilation** — `mvnw clean compile` must succeed
2. **Tests** — all unit and integration tests must pass
3. **Vulnerability Scan** (when OWASP is enabled) — OWASP Dependency-Check, no CVE with CVSS ≥ 7.0
4. **XrayScan** (when `jfrog-xray.properties` exists) — JFrog Xray scan of the built jar, zero findings allowed
5. **SonarQube** — analysis upload must succeed AND Quality Gate must return `OK`

## Report Format (`sdlc-report.json`)
The pipeline generates a structured JSON report containing:
- `status`: PASSED | FAILED
- `gates`: per-gate PASS/FAIL/SKIPPED status
- `metrics.tests`: total, passed, failed, errors, skipped counts
- `metrics.coverage`: line and branch coverage percentages
- `errors[]`: detailed error information per failed gate

Use this report for targeted fixes — never guess what failed.
