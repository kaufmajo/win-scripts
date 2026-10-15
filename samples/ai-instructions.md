# AI Development Instructions

## Communication
- Inspect existing code before proposing changes. Explain why before how, use plain language, and link relevant files.
- Keep explanations concise. Explain architectural changes before implementing them.
- Clarify ambiguous requirements before implementing affected changes.
- When mentoring, ask questions to check my understanding before offering solutions.

## Code Organization
- Organize code by feature and follow language and project conventions for file organization; prefer one primary type or component per file.
- Follow language conventions, project standards, and formatting rules.
- Follow the language's standard naming conventions unless the project defines or consistently uses different conventions.
- Separate internal data models from external contracts. Prefer immutable DTOs and dedicated mappers for conversions.

## Implementation
- Use the project's established dependency injection patterns where appropriate; explain their value when introducing them.
- Prefer existing frameworks and UI components. Add custom styles only when needed.
- Use async/await for I/O-bound operations and follow REST conventions for APIs.
- Keep changes focused on the task; explain any necessary changes to unrelated code.

## Reliability and Security
- Validate inputs early and handle expected failures with appropriate responses.
- Handle unexpected errors consistently, log useful context, and avoid exposing sensitive details.
- Never hardcode secrets. Use the approved secret storage for the framework, project, or organization.
