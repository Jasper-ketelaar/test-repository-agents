# Architecture Standards

This repository contains:
- Frontend: `factory` (Vite + React + TypeScript + Tailwind)
- Backend: `factory-backend` (Spring Boot + Kotlin + JPA)

## General Standards
- No inline code comments. Refactor for clarity instead. Only exception is legally required headers.
- Methods are max 15 lines. If a method exceeds this, extract helpers.
- One responsibility per class/file. Avoid “god” services or components.
- Prefer explicit names over abbreviations. No single-letter variables outside loops.
- No magic numbers or strings. Use named constants.
- Keep line length reasonable (aim for 100–120 chars).
- Don’t introduce new dependencies without clear need and approval.
- Use consistent formatting and linting defaults; don’t fight the tooling.
- Keep design and solutions minimalistic. Less is more.

## Frontend Standards (factory)
- Stack is fixed: Vite, React 19, TypeScript (strict), Tailwind v4, React Router.
- Use path aliases via `@/…` for all non-relative imports within `src`.
- Pages live in `src/pages`, layouts in `src/layouts`, shared UI in `src/components` and `src/components/ui`, hooks in `src/hooks`, types in `src/types`.
- Prefer Tailwind utilities and design tokens from `src/styles/index.css`. Avoid new CSS files unless Tailwind can’t express the needed styling.
- Reuse shadcn/Radix UI primitives in `src/components/ui` before creating new bespoke components.
- Component props are typed; no `any`. Data models live in `src/types`.
- Keep components small and focused; split presentation from data fetching.
- Use `useApi` for HTTP access and handle loading and error states explicitly.
- Use `cn`/`tailwind-merge` for class composition. No string concatenation for class names.
- Use React Router for navigation. Do not hardcode URLs outside routing and link components.

## Backend Standards (factory-backend)
- Stack is fixed: Spring Boot 4, Kotlin 2.2, Java 21, Maven, JPA, PostgreSQL.
- Layering is required: controllers -> services -> repositories. Controllers are thin.
- Entities are not returned directly from controllers. Always use DTOs.
- Validation is mandatory on request DTOs using `@Valid` and bean validation annotations.
- Transactions belong in services. Repositories stay simple (query methods only).
- Security: JWT is required for authenticated endpoints; no secrets in code. Use env vars.
- Configuration is in `application*.properties`; keep prod/test overrides minimal.
- API design is RESTful with clear status codes and error payloads.
- Avoid logic in configuration classes except wiring.
- Use Kotlin data classes for DTOs and request/response models.
