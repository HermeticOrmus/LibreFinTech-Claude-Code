# /payments

A quick-access command for payment-processing workflows in Claude Code.

## Trigger

`/payments [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing payment-processing implementation
- `generate` - Generate new payment-processing artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for payment-processing artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of payment-processing artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against payment-patterns patterns
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
## Payment Processing - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Payment Processing - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/payments analyze

# Generate new artifacts
/payments generate --context ./src

# Validate against best practices
/payments validate --verbose

# Generate documentation
/payments document --format markdown
```
