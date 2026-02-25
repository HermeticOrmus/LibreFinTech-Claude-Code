# /market-data

A quick-access command for market-data workflows in Claude Code.

## Trigger

`/market-data [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing market-data implementation
- `generate` - Generate new market-data artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for market-data artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of market-data artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against market-data-patterns patterns
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
## Market Data - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Market Data - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/market-data analyze

# Generate new artifacts
/market-data generate --context ./src

# Validate against best practices
/market-data validate --verbose

# Generate documentation
/market-data document --format markdown
```
