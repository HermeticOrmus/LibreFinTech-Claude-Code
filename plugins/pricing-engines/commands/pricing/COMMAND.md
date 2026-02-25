# /pricing

A quick-access command for pricing-engines workflows in Claude Code.

## Trigger

`/pricing [action] [options]`

## Input

### Actions
- `analyze` - Analyze existing pricing-engines implementation
- `generate` - Generate new pricing-engines artifacts
- `improve` - Suggest improvements to current implementation
- `validate` - Check implementation against best practices
- `document` - Generate documentation for pricing-engines artifacts

### Options
- `--context <path>` - Specify the file or directory to operate on
- `--format <type>` - Output format (markdown, json, yaml)
- `--verbose` - Include detailed explanations
- `--dry-run` - Preview changes without applying them

## Process

### Step 1: Context Gathering
- Read relevant files and configuration
- Identify the current state of pricing-engines artifacts
- Determine applicable standards and conventions

### Step 2: Analysis
- Evaluate against pricing-patterns patterns
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
## Pricing Engines - [Action] Complete

### Changes Made
- [List of changes]

### Validation
- [Checks passed]

### Next Steps
- [Recommended follow-up actions]
```

### Error
```
## Pricing Engines - [Action] Failed

### Issue
[Description of the problem]

### Suggested Fix
[How to resolve the issue]
```

## Examples

```bash
# Analyze current implementation
/pricing analyze

# Generate new artifacts
/pricing generate --context ./src

# Validate against best practices
/pricing validate --verbose

# Generate documentation
/pricing document --format markdown
```
