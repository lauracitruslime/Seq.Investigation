# SEQ Error Investigation Workflow

Automated workflow for investigating application errors from SEQ logs and creating Jira issues for tracking and resolution.

## Overview

This project provides an intelligent agent that:
- Monitors SEQ for high-volume error patterns
- Automatically classifies errors (transient, bug, external noise)
- Generates draft Jira tickets for review
- Creates approved Jira issues linked to an Epic
- Maintains a suppression file to avoid duplicate work

## Quick Start

1. **Prerequisites**:
   - PowerShell 7+
   - Access to SEQ instance
   - Jira Cloud account with API token
   - Required skill files in `C:\Users\laura\Ai\Skills\`:
     - `seq-api.md`
     - `jira-api.md`
     - `Load-Env.ps1`

2. **Setup Environment Variables**:
   ```powershell
   # Create .env file in C:\Users\laura\Ai\Skills\
   SEQ_TOKEN="your-seq-token"
   JIRA_TOKEN="your-jira-token"
   ```

3. **Initialize Suppression File**:
   ```powershell
   '{"suppressions":[]}' | Set-Content suppressions.json
   ```

4. **Run the Workflow**:
   ```powershell
   . C:\Users\laura\Ai\Skills\Load-Env.ps1
   # Copy and run the workflow script from AGENT.md
   Start-ErrorInvestigationWorkflow
   ```

## Documentation

See [AGENT.md](AGENT.md) for complete documentation including:
- Detailed workflow process
- Configuration options
- Error classification guidelines
- Complete PowerShell script
- Troubleshooting guide
- Best practices

## Configuration

Default settings (configurable in the script):
- **Time Range**: 12 hours
- **Minimum Error Count**: 10 occurrences
- **Max Templates**: 10 per run
- **Epic**: CLECOM-11226
- **Project**: CLECOM

## Files

- **AGENT.md**: Complete workflow documentation and PowerShell script
- **suppressions.json**: Tracks handled error templates (created on first run, not in git)
- **.gitignore**: Excludes operational data and secrets from version control

## Workflow Steps

1. Query SEQ for high-volume errors
2. Check suppression file for already-handled templates
3. Get detailed error instances
4. Classify errors (transient/bug/noise)
5. Generate draft Jira tickets
6. Review and approve drafts
7. Create Jira issues linked to Epic
8. Update suppression file

## Error Classifications

- **Transient**: Timeouts, connection issues → Auto-skipped
- **Bug**: Code defects → Jira for investigation
- **External/Noise**: Crawlers, invalid URLs → Jira suggesting log downgrade

## License

Internal use only - Citrus-Lime Ltd

## Support

For issues or questions, refer to the skill files or contact the development team.
