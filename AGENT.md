# SEQ Error Investigation & Jira Workflow Agent

## Overview
This workflow automates the process of investigating application errors from SEQ logs and creating Jira issues for tracking and resolution. The agent intelligently classifies errors, prevents duplicate tickets, and maintains a suppression file to avoid reprocessing already-handled error templates.

## Purpose
- **Monitor**: Query SEQ for high-volume error patterns
- **Classify**: Automatically categorize errors (transient, bug, external noise)
- **Review**: Generate draft Jira tickets for human review before creation
- **Track**: Create Jira issues linked to Epic CLECOM-11226
- **Suppress**: Remember handled error templates to avoid duplicate work

## Prerequisites

### Required Skills
This workflow depends on two skill files:
- **seq-api.md**: SEQ API integration for querying logs (`C:\Users\laura\Ai\Skills\seq-api.md`)
- **jira-api.md**: Jira API integration for issue management (`C:\Users\laura\Ai\Skills\jira-api.md`)

### Environment Setup
1. **Environment Variables**: Ensure `.env` file contains:
   ```
   SEQ_TOKEN="your-seq-token"
   JIRA_TOKEN="your-jira-token"
   ```

2. **Load Environment Variables**:
   ```powershell
   . C:\Users\laura\Ai\Skills\Load-Env.ps1
   ```

3. **Configuration**:
   - SEQ URL: `https://supportcs.citruslime.com`
   - Jira URL: `https://citruslime.atlassian.net`
   - Project: `CLECOM`
   - Epic: `CLECOM-11226`
   - Email: `laura@citruslime.com` (from git config)

## Workflow Process

### Step 1: Monitor SEQ for High-Volume Errors
Query SEQ for errors from the last 12 hours, grouped by message template, focusing on high-volume patterns.

### Step 2: Check Suppression File
Load `suppressions.json` and skip error templates that have already been addressed.

### Step 3: Get Error Details
For each new high-volume template, retrieve detailed error instances including stack traces and properties.

### Step 4: Classify Errors
Analyze error details and classify into one of three categories:
- **Transient** (timeouts, connection issues) → Skip/Ignore
- **Bug** (code defects, exceptions) → Create draft Jira for investigation
- **External/Noise** (crawlers, invalid URLs) → Create draft Jira suggesting log downgrade

### Step 5: Generate Draft Jiras
Create markdown draft tickets for user review with error details and recommended actions.

### Step 6: Review & Approve
User reviews classification and draft content, approves or modifies before creation.

### Step 7: Create Jira Issues
Create approved Jira issues linked to Epic CLECOM-11226 with full error context.

### Step 8: Update Suppression File
Add handled error templates to `suppressions.json` with classification and Jira issue key.

## Configuration

### Thresholds
```powershell
$config = @{
    TimeRangeHours = 12               # Look back window
    MinimumErrorCount = 10            # Only process errors with >10 occurrences
    MaxTemplatesPerRun = 10           # Process max 10 templates per run
    EpicKey = "CLECOM-11226"          # Parent epic for all issues
    ProjectKey = "CLECOM"             # Jira project
    SuppressionFile = "suppressions.json"
}
```

### Error Classification Patterns
```powershell
$patterns = @{
    Transient = @(
        "timeout", "timed out", "connection.*reset", "connection.*refused",
        "temporarily unavailable", "503 Service Unavailable", "504 Gateway Timeout"
    )
    ExternalNoise = @(
        "bot", "crawler", "spider", "http.*400", "invalid.*url",
        "malformed.*request", "user.*agent.*python", "user.*agent.*curl"
    )
    # If not matched above, classify as Bug
}
```

## Suppression File Format

### suppressions.json Schema
```json
{
  "suppressions": [
    {
      "eventType": "$564C0704",
      "messageTemplate": "Error loading FafCustomRepeater. Repeater ID : '{RepeaterID}'...",
      "classification": "Bug",
      "dateHandled": "2026-02-17T10:30:00Z",
      "jiraIssue": "CLECOM-11227",
      "notes": "Created Jira for investigation"
    },
    {
      "eventType": "$D27B469E",
      "messageTemplate": "Exception {Message}",
      "classification": "Transient",
      "dateHandled": "2026-02-17T10:30:00Z",
      "jiraIssue": null,
      "notes": "Timeout errors - ignored as transient"
    }
  ]
}
```

## Complete Workflow Script

### Main Workflow Function
```powershell
# Load environment variables
. C:\Users\laura\Ai\Skills\Load-Env.ps1

# Configuration
$config = @{
    SeqUrl = "https://supportcs.citruslime.com"
    JiraUrl = "https://citruslime.atlassian.net"
    JiraEmail = "laura@citruslime.com"
    ProjectKey = "CLECOM"
    EpicKey = "CLECOM-11226"
    TimeRangeHours = 12
    MinimumErrorCount = 10
    MaxTemplatesPerRun = 10
    SuppressionFile = "suppressions.json"
}

# Classification patterns
$transientPatterns = @(
    "timeout", "timed out", "connection.*reset", "connection.*refused",
    "temporarily unavailable", "503", "504"
)

$externalNoisePatterns = @(
    "bot", "crawler", "spider", "http.*400", "invalid.*url",
    "malformed.*request", "user.*agent.*python"
)

function Get-Suppressions {
    if (Test-Path $config.SuppressionFile) {
        $json = Get-Content $config.SuppressionFile -Raw | ConvertFrom-Json
        return $json.suppressions
    }
    return @()
}

function Add-Suppression {
    param(
        [string]$EventType,
        [string]$MessageTemplate,
        [string]$Classification,
        [string]$JiraIssue,
        [string]$Notes
    )
    
    $suppressions = Get-Suppressions
    
    $newSuppression = @{
        eventType = $EventType
        messageTemplate = $MessageTemplate
        classification = $Classification
        dateHandled = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        jiraIssue = $JiraIssue
        notes = $Notes
    }
    
    $suppressions += $newSuppression
    
    $json = @{ suppressions = $suppressions } | ConvertTo-Json -Depth 10
    Set-Content -Path $config.SuppressionFile -Value $json
    
    Write-Host "✓ Added suppression for $EventType" -ForegroundColor Green
}

function Get-SeqErrors {
    $headers = @{
        "X-Seq-ApiKey" = $env:SEQ_TOKEN
        "Content-Type" = "application/json"
    }
    
    $fromTime = (Get-Date).AddHours(-$config.TimeRangeHours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filter = "@Level = 'Error'"
    $uri = "$($config.SeqUrl)/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=200"
    
    $events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    
    # Group by EventType and get high-volume errors
    $grouped = $events | Group-Object -Property EventType | 
        Where-Object { $_.Count -ge $config.MinimumErrorCount } |
        Sort-Object Count -Descending |
        Select-Object -First $config.MaxTemplatesPerRun
    
    return $grouped
}

function Get-ErrorDetails {
    param([string]$EventType, [array]$AllEvents)
    
    $events = $AllEvents | Where-Object { $_.EventType -eq $EventType } | Select-Object -First 5
    return $events
}

function Get-ErrorClassification {
    param([array]$ErrorDetails)
    
    # Check for transient errors
    foreach ($event in $ErrorDetails) {
        $message = ($event.MessageTemplateTokens | ForEach-Object { $_.Text }) -join ' '
        $exception = $event.Exception
        $combined = "$message $exception"
        
        foreach ($pattern in $transientPatterns) {
            if ($combined -match $pattern) {
                return "Transient"
            }
        }
    }
    
    # Check for external noise
    foreach ($event in $ErrorDetails) {
        $props = @{}
        $event.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        
        $userAgent = $props['UserAgent']
        $url = $props['Url']
        $message = ($event.MessageTemplateTokens | ForEach-Object { $_.Text }) -join ' '
        $combined = "$message $userAgent $url"
        
        foreach ($pattern in $externalNoisePatterns) {
            if ($combined -match $pattern) {
                return "ExternalNoise"
            }
        }
    }
    
    # Default to Bug
    return "Bug"
}

function New-DraftJira {
    param(
        [string]$EventType,
        [string]$MessageTemplate,
        [int]$Count,
        [array]$ErrorDetails,
        [string]$Classification
    )
    
    $timeRange = "$($config.TimeRangeHours) hours"
    
    # Convert EventType from $XXXXXXXX to 0xXXXXXXXX format for SEQ filter
    $seqEventTypeFilter = if ($EventType -match '^\$([A-Fa-f0-9]+)$') {
        "@EventType = 0x$($Matches[1])"
    } else {
        "@Message like '%$MessageTemplate%'"
    }
    
    # Calculate logs per 12 hours
    $logsPerHalfDay = [math]::Round($Count * 12 / $config.TimeRangeHours)
    
    # Determine suggested action based on classification
    $suggestedAction = switch ($Classification) {
        "Bug" { "Fix underlying bug" }
        "ExternalNoise" { "Reduce log level or remove log" }
        "Transient" { "No action needed - transient error" }
        default { "Review and classify" }
    }
    
    $draft = @"
### Why?
Cleaning up logging issues improves quality of life for all involved in monitoring, and allows us to be more efficient in spotting real issues.

### What?
- **MessageTemplate**: ``$MessageTemplate``
- **Quantity of logs**: ~$logsPerHalfDay / 12 hours
- **Suggested action**: $suggestedAction
- **SEQ Filter**: ``$seqEventTypeFilter``

### How?

"@
    
    return $draft
}

function Show-DraftJiras {
    param([array]$Drafts)
    
    Write-Host "`n" + ("="*100) -ForegroundColor Cyan
    Write-Host "DRAFT JIRA ISSUES FOR REVIEW" -ForegroundColor Cyan
    Write-Host ("="*100) + "`n" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $Drafts.Count; $i++) {
        Write-Host "[$($i+1)/$($Drafts.Count)] " -NoNewline -ForegroundColor Yellow
        Write-Host $Drafts[$i].Classification -ForegroundColor $(if ($Drafts[$i].Classification -eq "Bug") { "Red" } else { "Yellow" })
        Write-Host $Drafts[$i].Draft
        Write-Host "`n" + ("-"*100) + "`n"
    }
}

function New-JiraIssue {
    param(
        [string]$Summary,
        [string]$Description,
        [string]$IssueType = "Bug"
    )
    
    $headers = @{
        "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($config.JiraEmail):$env:JIRA_TOKEN"))
        "Content-Type" = "application/json"
    }
    
    # Convert markdown description to Jira ADF format (simplified)
    $descriptionText = $Description -replace '#+ ', '' -replace '\[([^\]]+)\]\([^\)]+\)', '$1'
    
    $newIssue = @{
        fields = @{
            project = @{
                key = $config.ProjectKey
            }
            parent = @{
                key = $config.EpicKey
            }
            summary = $Summary
            description = @{
                type = "doc"
                version = 1
                content = @(
                    @{
                        type = "paragraph"
                        content = @(
                            @{
                                type = "text"
                                text = $descriptionText
                            }
                        )
                    }
                )
            }
            issuetype = @{
                name = $IssueType
            }
        }
    } | ConvertTo-Json -Depth 10
    
    $created = Invoke-RestMethod -Uri "$($config.JiraUrl)/rest/api/3/issue" -Headers $headers -Method Post -Body $newIssue
    
    return $created.key
}

# Main Workflow Execution
function Start-ErrorInvestigationWorkflow {
    Write-Host "Starting SEQ Error Investigation Workflow" -ForegroundColor Cyan
    Write-Host "Time Range: Last $($config.TimeRangeHours) hours" -ForegroundColor Gray
    Write-Host "Minimum Count: $($config.MinimumErrorCount)" -ForegroundColor Gray
    Write-Host "`n"
    
    # Step 1: Get high-volume errors from SEQ
    Write-Host "[1/8] Querying SEQ for high-volume errors..." -ForegroundColor Cyan
    $errorGroups = Get-SeqErrors
    Write-Host "✓ Found $($errorGroups.Count) high-volume error templates" -ForegroundColor Green
    
    # Step 2: Load suppressions
    Write-Host "`n[2/8] Loading suppression file..." -ForegroundColor Cyan
    $suppressions = Get-Suppressions
    $suppressedEventTypes = $suppressions | ForEach-Object { $_.eventType }
    Write-Host "✓ Loaded $($suppressions.Count) suppressed templates" -ForegroundColor Green
    
    # Step 3: Filter out suppressed templates
    Write-Host "`n[3/8] Filtering suppressed templates..." -ForegroundColor Cyan
    $newErrors = $errorGroups | Where-Object { $_.Name -notin $suppressedEventTypes }
    Write-Host "✓ $($newErrors.Count) new templates to process" -ForegroundColor Green
    
    if ($newErrors.Count -eq 0) {
        Write-Host "`nNo new error templates to process. All high-volume errors already handled." -ForegroundColor Yellow
        return
    }
    
    # Step 4-5: Classify errors and generate drafts
    Write-Host "`n[4/8] Getting error details and classifying..." -ForegroundColor Cyan
    $headers = @{
        "X-Seq-ApiKey" = $env:SEQ_TOKEN
        "Content-Type" = "application/json"
    }
    $fromTime = (Get-Date).AddHours(-$config.TimeRangeHours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filter = "@Level = 'Error'"
    $uri = "$($config.SeqUrl)/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=200"
    $allEvents = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    
    $drafts = @()
    foreach ($group in $newErrors) {
        $eventType = $group.Name
        $count = $group.Count
        $details = Get-ErrorDetails -EventType $eventType -AllEvents $allEvents
        $classification = Get-ErrorClassification -ErrorDetails $details
        
        if ($classification -eq "Transient") {
            Write-Host "  ⊘ $eventType - Classified as Transient, skipping" -ForegroundColor Gray
            Add-Suppression -EventType $eventType -MessageTemplate "Transient error" -Classification "Transient" -JiraIssue $null -Notes "Auto-classified as transient, ignored"
            continue
        }
        
        $messageTemplate = ($details[0].MessageTemplateTokens | ForEach-Object { 
            $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) 
        }) -join ''
        
        $draft = New-DraftJira -EventType $eventType -MessageTemplate $messageTemplate -Count $count -ErrorDetails $details -Classification $classification
        
        $drafts += @{
            EventType = $eventType
            MessageTemplate = $messageTemplate
            Count = $count
            Classification = $classification
            Draft = $draft
        }
        
        Write-Host "  ✓ $eventType - Classified as $classification" -ForegroundColor Green
    }
    
    Write-Host "✓ Generated $($drafts.Count) draft Jiras" -ForegroundColor Green
    
    if ($drafts.Count -eq 0) {
        Write-Host "`nAll new errors were classified as Transient. No Jiras to create." -ForegroundColor Yellow
        return
    }
    
    # Step 6: Show drafts for review
    Write-Host "`n[5/8] Displaying draft Jiras for review..." -ForegroundColor Cyan
    Show-DraftJiras -Drafts $drafts
    
    # Step 7: Prompt for approval
    Write-Host "`n[6/8] Review draft Jiras above" -ForegroundColor Cyan
    $response = Read-Host "Create these Jira issues? (yes/no/select)"
    
    if ($response -eq "no") {
        Write-Host "Workflow cancelled. No Jiras created." -ForegroundColor Yellow
        return
    }
    
    $draftsToCreate = $drafts
    if ($response -eq "select") {
        $indices = Read-Host "Enter draft numbers to create (comma-separated, e.g., 1,3,4)"
        $selected = $indices.Split(',') | ForEach-Object { [int]$_.Trim() - 1 }
        $draftsToCreate = $selected | ForEach-Object { $drafts[$_] }
    }
    
    # Step 8: Create Jira issues
    Write-Host "`n[7/8] Creating Jira issues..." -ForegroundColor Cyan
    foreach ($draft in $draftsToCreate) {
        try {
            # Title format: "Logging // Bug - name" or "Logging // Noise suppression - name"
            $titlePrefix = switch ($draft.Classification) {
                "Bug" { "Logging // Bug" }
                "ExternalNoise" { "Logging // Noise suppression" }
                default { "Logging // $($draft.Classification)" }
            }
            $name = $draft.MessageTemplate.Substring(0, [Math]::Min(60, $draft.MessageTemplate.Length))
            $summary = "$titlePrefix - $name"
            $jiraKey = New-JiraIssue -Summary $summary -Description $draft.Draft -IssueType "Bug"
            
            Write-Host "  ✓ Created $jiraKey" -ForegroundColor Green
            
            Add-Suppression -EventType $draft.EventType -MessageTemplate $draft.MessageTemplate -Classification $draft.Classification -JiraIssue $jiraKey -Notes "Jira created"
        }
        catch {
            Write-Host "  ✗ Failed to create Jira for $($draft.EventType): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "`n[8/8] Workflow complete!" -ForegroundColor Green
    Write-Host "Created $($draftsToCreate.Count) Jira issue(s)" -ForegroundColor Green
}

# Run the workflow
Start-ErrorInvestigationWorkflow
```

## Usage

### First Time Setup
1. Ensure environment variables are loaded
2. Create initial (empty) suppressions.json:
   ```powershell
   '{"suppressions":[]}' | Set-Content suppressions.json
   ```

### Running the Workflow
```powershell
# Run the complete workflow
Start-ErrorInvestigationWorkflow

# The workflow will:
# - Query SEQ for high-volume errors
# - Skip already-suppressed templates
# - Classify new errors
# - Show draft Jiras for review
# - Create approved Jiras linked to Epic
# - Update suppression file
```

### Daily Usage
Simply run the workflow each day:
```powershell
. C:\Users\laura\Ai\Skills\Load-Env.ps1
Start-ErrorInvestigationWorkflow
```

The suppression file ensures you won't reprocess already-handled error templates.

## Error Classification Guide

### Transient Errors (Auto-Skip)
**Characteristics**:
- Temporary network issues
- Timeout errors
- Connection resets
- Service temporarily unavailable

**Examples**:
- "Connection timed out"
- "503 Service Unavailable"
- "Database connection refused"

**Action**: Automatically skipped, added to suppressions with no Jira

### Bugs (Create Jira)
**Characteristics**:
- Code exceptions (NullReference, ArgumentException, etc.)
- Logic errors
- Unexpected application behavior
- Consistent failures

**Examples**:
- "NullReferenceException"
- "Error loading repeater"
- "Failed to process order"

**Action**: Create Jira for investigation with full details

### External Noise (Create Jira with Log Downgrade Suggestion)
**Characteristics**:
- Crawler/bot traffic
- Invalid URLs or malformed requests
- External factors outside our control
- Non-actionable errors

**Examples**:
- "Invalid URL format from crawler"
- "400 Bad Request from bot"
- "Malformed request from Python script"

**Action**: Create Jira suggesting log downgrade or removal

## Troubleshooting

### No Errors Found
**Issue**: Workflow reports 0 high-volume errors
**Solutions**:
- Reduce `MinimumErrorCount` threshold
- Increase `TimeRangeHours` window
- Check SEQ is accessible and token is valid

### All Errors Already Suppressed
**Issue**: All errors are in suppression file
**Solutions**:
- This is normal for subsequent runs
- Review suppression file to ensure it's accurate
- Delete suppression file to start fresh (careful!)

### Jira Creation Fails
**Issue**: Error when creating Jira issues
**Solutions**:
- Verify JIRA_TOKEN is valid
- Check Epic CLECOM-11226 exists and is accessible
- Ensure you have permission to create issues in CLECOM project
- Verify issue type "Bug" exists in project

### Classification Seems Wrong
**Issue**: Errors classified incorrectly
**Solutions**:
- Review and adjust pattern matching in `$transientPatterns` and `$externalNoisePatterns`
- Use "select" option when approving to skip incorrectly classified errors
- Manually classify in draft review step

### Suppression File Corrupted
**Issue**: Error loading suppressions.json
**Solutions**:
- Validate JSON syntax
- Restore from backup if available
- Start fresh with: `'{"suppressions":[]}' | Set-Content suppressions.json`

## Best Practices

1. **Run Daily**: Execute the workflow once per day during a review period
2. **Review Drafts**: Always review draft Jiras before approving creation
3. **Refine Patterns**: Adjust classification patterns based on your error types
4. **Backup Suppressions**: Keep a backup of suppressions.json
5. **Epic Hygiene**: Periodically review Epic CLECOM-11226 and close resolved issues
6. **Threshold Tuning**: Adjust `MinimumErrorCount` based on your environment
7. **Time Window**: Use 12-24 hour windows to capture patterns without overwhelming data

## Next Steps

After running the workflow:
1. Review created Jira issues in Epic CLECOM-11226
2. Assign issues to appropriate team members
3. Prioritize based on error frequency and impact
4. Track resolution progress in Jira
5. Run workflow again next day to catch new error patterns
