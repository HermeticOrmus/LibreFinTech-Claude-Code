# /kyc-aml

A quick-access command for kyc-aml workflows in Claude Code.

## Trigger

`/kyc-aml [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing kyc-aml implementation
- `generate` - Generate new kyc-aml artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for kyc-aml artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of kyc-aml artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against kyc-aml-patterns patterns
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
## Kyc Aml - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Kyc Aml - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/kyc-aml analyze

# Generate new artifacts
/kyc-aml generate --context ./src

# Validate against best practices
/kyc-aml validate --verbose

# Generate documentation
/kyc-aml document --format markdown
```
