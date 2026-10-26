---
name: improve-codenase-systems
description: Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
disable-model-invocation: true
---

# Improve Codenase Systems

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

This command is _informed_ by the project's domain model and built on a shared design vocabulary:

- Call the Skill tool with "codebase-design" for the architecture vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and its principles (the deletion test, "the interface is the test surface", "one adapter = hypothetical seam, two = real"). Use these terms exactly in every suggestion, and don't drift into "component," "service," "API," or "boundary."
- The domain language in `CONTEXT.md` gives names to good seams; ADRs in `docs/adr/` record decisions this command should not re-litigate.

## Scan Checklist

### Architecture & Code Organization

- duplicated or highly similar code that should be reused
- business logic placed directly inside UI components when it should be extracted
- API/data fetching logic duplicated across components
- API calls implemented directly in components instead of an appropriate service/query layer
- components with too many responsibilities
- components that are unnecessarily large and should be split
- hooks that contain unrelated responsibilities
- utilities/helpers duplicated across the codebase
- inappropriate abstraction or abstraction created without actual reuse
- unnecessary abstraction or over-engineering
- tight coupling between unrelated components or modules
- circular dependencies
- incorrect dependency direction
- feature-specific logic placed in global/shared modules unnecessarily
- shared/common modules becoming dumping grounds
- inconsistent project structure for similar features

### React / Next.js

- unnecessary useEffect
- useEffect used for derived state
- state that can be derived instead of stored
- duplicated state
- unnecessary local state
- state synchronization that can cause inconsistent data
- stale closure issues
- missing cleanup for effects, subscriptions, timers, or event listeners
- side effects executed during render
- unnecessary re-renders
- expensive computation executed on every render
- incorrect or unnecessary useMemo/useCallback
- memoization used without measurable benefit
- missing memoization for clearly expensive operations
- unstable keys in list rendering
- array index used as key when list order can change
- prop drilling that should be solved with a more appropriate state/data architecture
- unnecessary Context usage causing broad re-renders
- incorrect dependency array
- disabling eslint hook dependency rules without a valid reason

### Next.js Specific

- unnecessary "use client"
- Server Components unnecessarily converted into Client Components
- data fetching on the client when server-side fetching is more appropriate
- duplicated server and client data fetching
- incorrect caching strategy
- missing or incorrect revalidation strategy
- unnecessary dynamic rendering
- unnecessary dynamic imports
- heavy client-side dependencies that could remain server-side
- server-only code imported into client code
- environment variables exposed to the client unnecessarily
- incorrect usage of Server Actions
- missing loading or error boundaries where appropriate

### Data Fetching & State Management

- duplicated API requests
- unnecessary repeated fetching
- missing request cancellation where race conditions can occur
- stale data issues
- race conditions between requests
- missing loading states
- missing error states
- missing empty states
- inconsistent error handling
- data transformed repeatedly in multiple places
- server state incorrectly stored as local/global client state
- global state used for local component state
- local state used where shared state management is required
- missing debounce or throttle for search, resize, scroll, or frequent user input
- unnecessary polling
- incorrect cache invalidation

### Performance

- unnecessary re-renders
- expensive operations during render
- large lists rendered without virtualization when necessary
- unnecessary large bundle dependencies
- importing entire libraries when smaller imports are available
- duplicate dependencies with overlapping functionality
- unnecessary images/assets loaded eagerly
- missing lazy loading where beneficial
- unnecessary network requests
- sequential independent requests that can run in parallel
- unnecessary client-side computation
- avoidable bundle size increase
- memory leaks caused by listeners, timers, subscriptions, or retained references

### UI / UX

- duplicated UI patterns that should be reusable components
- hardcoded UI that should be generated from reusable components or configuration
- hardcoded values that should come from constants/configuration
- inconsistent loading behavior
- inconsistent error handling
- inconsistent empty states
- missing disabled/loading state for async actions
- duplicate submissions
- missing feedback for long-running operations
- UI state that can become inconsistent with server state
- forms without proper validation
- validation logic duplicated across components
- validation rules inconsistent with backend constraints
- missing responsive behavior where applicable

### Accessibility

- non-semantic HTML where semantic elements are appropriate
- interactive elements implemented with non-interactive elements
- missing accessible labels
- missing aria attributes when required
- keyboard inaccessible interactions
- missing focus management
- dialogs/modals without proper focus handling
- images without meaningful alt text
- form controls without associated labels

### TypeScript

- usage of any
- unnecessary type assertions using "as"
- unsafe type assertions
- duplicated type definitions
- manually defined types that should be inferred
- ambiguous or overly generic types
- missing explicit types where inference is insufficient
- inconsistent nullable/optional handling
- type definitions placed in inappropriate files
- feature/domain types mixed with unrelated UI files
- API response types duplicated instead of reused
- incorrect use of interface vs type based on project conventions

### Code Quality

- ambiguous function names
- ambiguous variable names
- misleading names
- dead code
- unused imports
- unused dependencies
- commented-out code
- magic numbers or strings
- duplicated constants
- hardcoded configuration
- unnecessary complexity
- deeply nested conditions that can be simplified
- duplicated conditional logic
- functions doing too many things
- components doing too many things
- unclear or inconsistent error messages

### Backend / NestJS

- business logic implemented inside controllers
- database logic implemented inside controllers
- infrastructure logic mixed with business/domain logic
- duplicated business logic across services
- duplicated database access logic
- services with too many responsibilities
- classes violating single responsibility
- functions with too many responsibilities
- overly large services that should be split
- inappropriate abstraction
- unnecessary abstraction or over-engineering
- circular dependencies
- incorrect dependency direction
- module boundary violations
- tight coupling between modules
- direct access to another module's internal implementation
- feature-specific logic placed in shared/common modules unnecessarily
- shared/common modules becoming dumping grounds
- duplicated utilities/helpers

### NestJS Framework

- controller containing business logic
- controller directly accessing Prisma/database
- missing DTO for request input where DTO validation is appropriate
- missing validation decorators
- validation implemented manually when DTO validation should handle it
- incorrect DTO validation
- DTO used for unrelated responsibilities
- entity/database model exposed directly as API response
- missing or inconsistent serialization/transformation
- guards implemented incorrectly
- authorization checks missing
- resource ownership checks missing
- authentication handled manually instead of using appropriate guards/middleware
- business logic implemented inside guards/interceptors unnecessarily
- incorrect usage of middleware, guards, interceptors, pipes, or filters
- duplicated exception handling
- missing global exception handling where appropriate
- dependency injected but not actually needed
- unnecessary request-scoped providers
- incorrect provider/module scope

### API Design

- ambiguous endpoint naming
- inconsistent REST conventions
- inconsistent request/response structure
- inconsistent error response format
- sensitive data returned in API response
- missing pagination for potentially large datasets
- missing filtering limits
- unbounded request parameters
- missing validation for query/path/body parameters
- API exposing internal implementation details
- inconsistent status codes
- idempotency issues
- duplicate request processing
- missing rate limiting for sensitive endpoints
- breaking API changes without versioning strategy where applicable

### Prisma & Database

- Prisma/database query directly inside controller
- duplicated Prisma query logic
- Prisma access scattered across unrelated modules without clear data access boundaries
- N+1 queries
- database queries inside loops
- sequential independent queries that can run in parallel
- fetching unnecessary fields
- missing select when only a subset of fields is required
- unnecessary include
- over-fetching relations
- loading large relation collections into memory
- findMany without pagination for potentially large datasets
- offset pagination used for very large datasets where cursor pagination is more appropriate
- incorrect cursor pagination
- pagination without deterministic orderBy
- missing filtering constraints
- duplicate count/data queries that can be optimized
- unnecessary database round trips
- findFirst used when findUnique is possible
- findUnique used with fields that are not actually unique
- unsafe raw SQL
- unnecessary raw SQL when Prisma can handle the query
- Prisma errors leaked directly to API responses
- missing handling for expected Prisma errors
- inconsistent nullable/optional handling between DTO, application code, and Prisma schema
- incorrect usage of checked/unchecked Prisma inputs

### Transactions & Data Integrity

- multi-step database operations without a required transaction
- transaction scope unnecessarily large
- external API/network calls executed inside database transactions
- long-running operations inside transactions
- incorrect interactive transaction usage
- transaction used where a batch transaction would be sufficient
- operations that can leave partial/inconsistent data
- race conditions during read-modify-write operations
- missing unique constraints for data that must be unique
- missing database constraints for important invariants
- application-only validation where database constraints are also required
- incorrect cascade delete behavior
- dangerous cascade delete
- inconsistent soft-delete filtering
- queries that accidentally include soft-deleted records
- operations that bypass soft-delete rules

### Prisma Schema

- missing index for frequently queried fields
- missing composite index for common multi-field queries
- unnecessary indexes
- duplicated or redundant indexes
- incorrect unique constraints
- missing unique constraints
- incorrect nullable/required fields
- incorrect relation definitions
- missing or inappropriate onDelete/onUpdate behavior
- string fields that should use enums
- duplicated enum/value definitions
- inconsistent naming
- schema changes that may cause data loss
- schema changes inconsistent with existing migrations
- migration risks that require manual data migration

### Async & Concurrency

- unnecessary sequential await operations
- independent async operations that can run in parallel
- unhandled promise rejection
- fire-and-forget async operations without error handling
- race conditions
- missing concurrency control
- duplicate processing caused by concurrent requests
- missing idempotency for retryable operations
- retry logic without limits
- retry logic without backoff where appropriate
- retrying non-idempotent operations unsafely
- missing timeout for external service calls
- blocking/synchronous operations inside request handling

### Error Handling

- empty catch blocks
- swallowed errors
- catch blocks that lose the original error/context
- generic Error used instead of appropriate application/domain exceptions
- inconsistent exception handling
- sensitive internal information exposed in errors
- missing error handling for external dependencies
- errors logged but not propagated when they should be
- errors propagated without meaningful context
- retryable and non-retryable errors handled identically

### Security

- missing authentication
- missing authorization
- IDOR/resource ownership vulnerabilities
- trusting user input without validation
- unsafe raw SQL
- SQL injection risk
- command injection risk
- path traversal
- SSRF
- unsafe file upload handling
- missing file size validation
- missing MIME/type validation
- trusting client-provided file metadata
- hardcoded secrets or credentials
- secrets exposed in logs
- sensitive information logged
- sensitive information returned in API responses
- insecure CORS configuration
- missing rate limiting for sensitive operations
- insecure token handling
- missing permission checks
- unsafe deserialization

### Observability & Reliability

- missing structured logging
- inconsistent log format
- sensitive data in logs
- missing error context
- missing correlation/request ID propagation where appropriate
- missing logging for critical failures
- excessive logging in hot paths
- missing health checks for critical dependencies
- missing graceful shutdown handling
- resource leaks
- timers/listeners/subscriptions not cleaned up
- connections not closed properly
- background jobs without failure handling
- critical operations without metrics or monitoring hooks where appropriate

## Process

### 1. Explore

**Scope before you scan: YAGNI.** Deepening a module pays off by making future changes to it easier, so put extra weight on the parts of the codebase that have recently changed. Decide *where* to look before you look:

- If the user named a direction (a module, a subsystem, a pain point), take it, and skip the inference below.
- Otherwise, walk back a good stretch of the commit history (`git log --oneline`) to find the codebase's hot spots, the files and areas that keep coming up, and let those paths pull your attention first. If the changes are scattered with no clear hot spot, widen the net.

Read the project's domain glossary (`CONTEXT.md`) and any ADRs in the area you're touching first.

Then spawn a sub-agent to walk the codebase. Don't follow rigid heuristics; explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow**, with an interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the repo. Resolve the temp dir from `$TMPDIR`, falling back to `/tmp` (or `%TEMP%` on Windows), and write to `<tmpdir>/architecture-review-<timestamp>.html` so each run gets a fresh file. Open it for the user (`xdg-open <path>` on Linux, `open <path>` on macOS, `start <path>` on Windows) and tell them the absolute path.

The report uses **Tailwind via CDN** for layout and styling, and **Mermaid via CDN** for diagrams where a graph/flow/sequence reliably communicates the structure. Mix Mermaid with hand-crafted CSS/SVG visuals: use Mermaid when relationships are graph-shaped (call graphs, dependencies, sequences), and hand-built divs/SVG when you want something more editorial (mass diagrams, cross-sections, collapse animations). Each candidate gets a **before/after visualisation**. Be visual.

For each candidate, render a card with:

- **Files**: which files/modules are involved
- **Problem**: why the current architecture is causing friction
- **Solution**: plain English description of what would change
- **Benefits**: explained in terms of locality and leverage, and how tests would improve
- **Before / After diagram**: side-by-side, custom-drawn, illustrating the shallowness and the deepening
- **Recommendation strength**: one of `Strong`, `Worth exploring`, `Speculative`, rendered as a badge

End the report with a **Top recommendation** section: which candidate you'd tackle first and why.

**Use CONTEXT.md vocabulary for the domain, and the `/codebase-design` vocabulary for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module," not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly in the card (e.g. a warning callout: _"contradicts ADR-0007, but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram patterns, and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, call the Skill tool with "grilling" to walk the decision tree with them: constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions crystallize; call the Skill tool with "domain-modeling" to keep the domain model current as you go:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md`. Create the file lazily if it doesn't exist.
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing; skip ephemeral reasons ("not worth it right now") and self-evident ones.
- **Want to explore alternative interfaces for the deepened module?** Call the Skill tool with "codebase-design" and use its design-it-twice parallel sub-agent pattern.
