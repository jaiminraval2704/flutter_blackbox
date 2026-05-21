# Contributing to Flutter BlackBox 🐞

Thank you for considering contributing to Flutter BlackBox! Every contribution helps make Flutter debugging better for the entire community.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Features](#suggesting-features)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

---

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/flutter_blackbox.git
   cd flutter_blackbox
   ```
3. **Add the upstream remote**:
   ```bash
   git remote add upstream https://github.com/jaiminraval2704/flutter_blackbox.git
   ```

---

## Development Setup

### Prerequisites

- Flutter SDK `>=3.13.0`
- Dart SDK `>=3.0.0`

### Install dependencies

```bash
flutter pub get
```

### Run tests

```bash
flutter test
```

### Run static analysis

```bash
dart analyze
```

### Format code

```bash
dart format .
```

### Check pub.dev score locally

```bash
dart pub global activate pana
pana .
```

---

## Making Changes

1. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** — follow our [Coding Standards](#coding-standards)

3. **Add tests** for any new functionality

4. **Run the full quality check**:
   ```bash
   dart format .
   dart analyze
   flutter test
   ```

5. **Commit** with a clear message:
   ```
   feat: add environment switcher panel
   fix: network panel crash on empty response
   docs: update README with new API examples
   ```

---

## Pull Request Process

1. Update the `CHANGELOG.md` with your changes under an `## [Unreleased]` section
2. Ensure all tests pass and there are no analyzer warnings
3. Update documentation if you changed any public API
4. Fill out the PR template completely
5. Request review from a maintainer

### PR Title Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use For |
|--------|---------|
| `feat:` | New features |
| `fix:` | Bug fixes |
| `docs:` | Documentation changes |
| `perf:` | Performance improvements |
| `test:` | Adding or updating tests |
| `refactor:` | Code refactoring |
| `chore:` | Maintenance tasks |

---

## Coding Standards

### Dart Style

- Follow the [Effective Dart](https://dart.dev/effective-dart) guidelines
- Run `dart format .` before committing
- No analyzer warnings (`dart analyze` must pass clean)

### Documentation

- Add `///` doc comments to all public APIs
- Include code examples in doc comments where helpful
- Keep comments up to date with code changes

### Testing

- Write unit tests for all new store/model logic
- Write widget tests for new UI panels
- Maintain existing test coverage — don't break existing tests

### Architecture

- **Core logic** goes in `lib/src/core/` (stores, models, adapters)
- **UI panels** go in `lib/src/overlay/panels/`
- **Shared widgets** go in `lib/src/overlay/widgets/`
- **Adapter interfaces** go in `lib/src/adapters/`
- Keep panels stateless where possible, subscribe to store streams
- Follow the "Observe Only, Never Modify" philosophy — adapters should never change app behavior

---

## Reporting Bugs

Use the [Bug Report template](https://github.com/jaiminraval2704/flutter_blackbox/issues/new?template=bug_report.md) and include:

- Flutter/Dart version (`flutter --version`)
- BlackBox version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

---

## Suggesting Features

Use the [Feature Request template](https://github.com/jaiminraval2704/flutter_blackbox/issues/new?template=feature_request.md) and include:

- Clear description of the feature
- Use case / problem it solves
- Example API design (if applicable)

---

## 💡 Good First Issues

Look for issues tagged with [`good first issue`](https://github.com/jaiminraval2704/flutter_blackbox/labels/good%20first%20issue) — these are great starting points for new contributors!

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
