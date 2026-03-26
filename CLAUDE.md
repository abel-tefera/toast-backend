# Toast Stack Architecture

This is a monorepo that uses **git submodules** to compose the full Toast platform.
Each submodule is its own GitHub repository under `abel-tefera`.

## Submodules

| Submodule | Description |
|-----------|-------------|
| `toast-frontend` | Frontend application |
| `toast-backend` | Backend API server |
| `toast-database` | Database migrations and schemas |

## Contributing

- When fixing bugs, open pull requests in the **individual submodule repos**, not in this parent repo.
- A single bug fix may require PRs in **multiple** submodule repos (e.g., a backend change plus a migration).
- After submodule PRs are merged, update the submodule pointers in this parent repo.
