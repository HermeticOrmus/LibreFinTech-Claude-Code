# Contributing to LibreFinTech

Thank you for your interest in contributing to LibreFinTech. This project thrives on community expertise across the diverse domains of financial technology.

## Core Principle

Every contribution must answer "yes" to: **Does this empower developers?**

We reject dark patterns, surveillance capitalism, addiction mechanics, and extractive design. We build tools that teach, tools that respect autonomy, and tools that create long-term value.

## How to Contribute

### Improving Existing Plugins

1. Fork the repository
2. Create a branch: `feature/plugin-name-improvement` or `fix/plugin-name-issue`
3. Make your changes
4. Submit a pull request

### Adding a New Plugin

New plugins must include all four files:

```
plugins/{plugin-name}/
├── README.md           # 50-80 lines, description + examples
├── agents/
│   └── {name}/AGENT.md # 80-150 lines, identity + expertise + behavior
├── commands/
│   └── {name}/COMMAND.md # 60-100 lines, trigger + process + output
└── skills/
    └── {name}/SKILL.md  # 60-100 lines, patterns + anti-patterns
```

### Plugin Quality Checklist

- [ ] Agent has a clear identity, defined expertise areas, and behavioral guidelines
- [ ] Command has explicit trigger syntax, input requirements, and output format
- [ ] Skill includes both patterns and anti-patterns with rationale
- [ ] README includes practical examples
- [ ] All regulatory references cite specific standards (not vague allusions)
- [ ] Code examples compile or run without modification
- [ ] No PII, credentials, or sensitive data in examples

### Updating Learning Paths

Learning paths should remain practical and progressive. When adding content:

- Beginner: Concepts a developer new to FinTech needs on day one
- Intermediate: Patterns for production integration work
- Advanced: Architecture for high-throughput, regulated systems

### Improving Hooks

Hooks must remain POSIX-compatible and fast (under 500ms execution). Test on both Linux and macOS.

## Code Standards

- **Commit format**: `type(scope): description` (feat, fix, docs, refactor)
- **Branch naming**: `feature/description`, `fix/description`
- **Markdown**: ATX headings, fenced code blocks, reference-style links for repeated URLs
- **Line length**: 100 characters for prose, no limit for tables and code

## Review Process

1. All PRs require at least one review
2. Plugin PRs are reviewed for technical accuracy in the financial domain
3. Hooks PRs are reviewed for security implications
4. Learning path PRs are reviewed for pedagogical progression

## Reporting Issues

Use GitHub Issues with the appropriate template. Include:

- Which plugin, hook, or learning path is affected
- What behavior you expected vs. what you observed
- Your Claude Code version and OS

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating, you agree to uphold a respectful, inclusive environment.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
