# /fin-report

A quick-access command for financial-reporting workflows in Claude Code.

## Trigger

`/fin-report [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing financial-reporting implementation
- `generate` - Generate new financial-reporting artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for financial-reporting artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of financial-reporting artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against fin-reporting-patterns patterns
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
## Financial Reporting - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Financial Reporting - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/fin-report analyze

# Generate new artifacts
/fin-report generate --context ./src

# Validate against best practices
/fin-report validate --verbose

# Generate documentation
/fin-report document --format markdown
```
