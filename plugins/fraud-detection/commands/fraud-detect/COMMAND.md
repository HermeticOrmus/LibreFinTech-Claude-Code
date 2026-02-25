# /fraud-detect

A quick-access command for fraud-detection workflows in Claude Code.

## Trigger

`/fraud-detect [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing fraud-detection implementation
- `generate` - Generate new fraud-detection artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for fraud-detection artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of fraud-detection artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against fraud-detection-patterns patterns
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
## Fraud Detection - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Fraud Detection - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/fraud-detect analyze

# Generate new artifacts
/fraud-detect generate --context ./src

# Validate against best practices
/fraud-detect validate --verbose

# Generate documentation
/fraud-detect document --format markdown
```
