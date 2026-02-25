# /settlement

A quick-access command for real-time-settlement workflows in Claude Code.

## Trigger

`/settlement [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing real-time-settlement implementation
- `generate` - Generate new real-time-settlement artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for real-time-settlement artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of real-time-settlement artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against settlement-patterns patterns
- Identify gaps, issues, and opportunities
- Prioritize findings by impact and effort

### Step 3: Execution
- Apply the requested action
- Generate or modify artifacts as needed
- Validate changes against requirements

### Step 4: Output
- Present results in the requested format
- Include actionable next steps
- Flag any items requiring human decision

## Output

### Success
```
## Real Time Settlement - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Real Time Settlement - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/settlement analyze

# Generate new artifacts
/settlement generate --context ./src

# Validate against best practices
/settlement validate --verbose

# Generate documentation
/settlement document --format markdown
```
