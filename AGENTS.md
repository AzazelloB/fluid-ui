# Project instructions

- Do not create or run unit tests, including tests in temporary directories.
  Validate changes with compiler checks and manual runtime verification instead.
- Keep README.md focused on prerequisites and how to run the project.
- Keep each demo's layout and behavior in its own file, separate from generic UI
  mechanisms.
- Use stable element IDs to connect data owned by different engine systems.
  Keep records dense when a system can iterate only the items it processes,
  such as visible elements or active transitions. Store optional data only
  where it is used. Prefer concrete arrays and lookups over a generic ECS.
- Discuss substantial architectural changes before implementing them. Push back
  when a proposal introduces unnecessary complexity or conflicts with the design.
