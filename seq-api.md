# SEQ API Integration Skill

## Description
This skill enables interaction with SEQ (Datalust) structured logging platform using PowerShell and the SEQ REST API. Query, filter, and analyze application logs by level, time range, and message templates.

## Prerequisites
- PowerShell 7+
- SEQ instance with API access
- Environment variables configured in `.env` file

## Setup

### 1. Environment Variables
Ensure your `.env` file contains the SEQ API token(s):
```
SEQ_TOKEN="your-seq-api-token"
POS_SEQ_TOKEN="your-pos-seq-api-token"
```

### 2. Load Environment Variables
Before using SEQ commands, load the environment variables:
```powershell
. .\Load-Env.ps1
```

This will load the `SEQ_TOKEN` and other environment variables for the current session.

### 3. Configuration
- **SEQ URL**: `https://supportcs.citruslime.com`
- **API Token**: Loaded from `$env:SEQ_TOKEN`
- Multiple SEQ instances can use different tokens (e.g., `$env:POS_SEQ_TOKEN`)

## Authentication
SEQ API uses API key authentication via the `X-Seq-ApiKey` header:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}
```

## Common Operations

### Get Recent Events
Retrieve the most recent log events:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

$events = Invoke-RestMethod -Uri "https://supportcs.citruslime.com/api/events?count=20" -Headers $headers -Method Get

$events | ForEach-Object {
    $messageTemplate = ($_.MessageTemplateTokens | ForEach-Object { $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) }) -join ''
    [PSCustomObject]@{
        Timestamp = $_.Timestamp
        Level = $_.Level
        Message = $messageTemplate
    }
} | Format-Table -AutoSize
```

### Get Errors from Last 12 Hours with Message Template Counts (Top 20)
This is the primary use case - get error counts grouped by message template:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Calculate time range (last 12 hours)
$fromTime = (Get-Date).AddHours(-12).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Query for Error level events
$filter = "@Level = 'Error'"
$uri = "https://supportcs.citruslime.com/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=100"

$events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

# Group by EventType (message template) and get top 20
$grouped = $events | Group-Object -Property EventType | Sort-Object Count -Descending | Select-Object -First 20

Write-Host "Top 20 Error Message Templates (Last 12 Hours)" -ForegroundColor Cyan
Write-Host "="*100 -ForegroundColor Cyan

$results = $grouped | ForEach-Object {
    $sample = $_.Group[0]
    $messageTemplate = ($sample.MessageTemplateTokens | ForEach-Object { 
        $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) 
    }) -join ''
    
    [PSCustomObject]@{
        EventType = $_.Name
        Count = $_.Count
        MessageTemplate = $messageTemplate
        LastSeen = $sample.Timestamp
    }
}

$results | Format-Table -Property Count, EventType, @{Name="MessageTemplate"; Expression={$_.MessageTemplate}; Width=60}, LastSeen -AutoSize -Wrap

Write-Host "`nTotal Errors: $($events.Count)" -ForegroundColor Yellow
```

### Get Detailed Messages for a Specific Template
Once you identify an error template of interest, get detailed instances with property values:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Get all errors from last 12 hours
$fromTime = (Get-Date).AddHours(-12).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$filter = "@Level = 'Error'"
$uri = "https://supportcs.citruslime.com/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=100"
$allEvents = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

# Filter for specific EventType (e.g., from the grouped results above)
$eventType = '$564C0704'  # Replace with the EventType you want to investigate
$events = $allEvents | Where-Object { $_.EventType -eq $eventType } | Select-Object -First 10

Write-Host "Detailed Messages for EventType: $eventType" -ForegroundColor Cyan
Write-Host "="*100

$events | ForEach-Object {
    $messageTemplate = ($_.MessageTemplateTokens | ForEach-Object { 
        $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) 
    }) -join ''
    
    Write-Host "`n[$($_.Timestamp)] $($_.Level)" -ForegroundColor Yellow
    Write-Host "Message: $messageTemplate" -ForegroundColor White
    
    # Display all properties
    Write-Host "Properties:" -ForegroundColor Cyan
    $_.Properties | Where-Object { $_.Name -notlike "AppDomain*" -and $_.Name -ne "DLL Version" } | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Gray
    }
    
    # Display exception if present
    if ($_.Exception) {
        Write-Host "Exception:" -ForegroundColor Red
        Write-Host $_.Exception -ForegroundColor Red
    }
    
    Write-Host "-"*100
}
```

### Query Events by Different Levels
Search for events at different log levels:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Available levels: Verbose, Debug, Information, Warning, Error, Fatal
$level = "Warning"  # Change as needed
$fromTime = (Get-Date).AddHours(-12).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$filter = "@Level = '$level'"

$uri = "https://supportcs.citruslime.com/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=50"
$events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$events | ForEach-Object {
    $messageTemplate = ($_.MessageTemplateTokens | ForEach-Object { 
        $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) 
    }) -join ''
    [PSCustomObject]@{
        Timestamp = $_.Timestamp
        Level = $_.Level
        Message = $messageTemplate
    }
} | Format-Table -AutoSize -Wrap
```

### Search Events by Text or Property
Search for events containing specific text or property values:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Search for events containing specific text
$searchText = "NullReferenceException"
$filter = "@Message like '%$searchText%'"
$fromTime = (Get-Date).AddHours(-24).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$uri = "https://supportcs.citruslime.com/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=20"
$events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$events | Select-Object -First 10 | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = $_.Timestamp
        Level = $_.Level
        Exception = $_.Exception
    }
} | Format-List
```

### Search by Property Value
Filter events by specific property values:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Search for events with a specific property value
$filter = "RepeaterID = 1"
$fromTime = (Get-Date).AddHours(-12).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$uri = "https://supportcs.citruslime.com/api/events?filter=$([uri]::EscapeDataString($filter))&fromDateUtc=$fromTime&count=20"
$events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$events | ForEach-Object {
    $props = @{}
    $_.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
    
    [PSCustomObject]@{
        Timestamp = $_.Timestamp
        Level = $_.Level
        RepeaterID = $props['RepeaterID']
        RepeaterTitle = $props['RepeaterTitle']
    }
} | Format-Table -AutoSize
```

### Get Events for Custom Time Range
Query events for a specific date/time range:
```powershell
$headers = @{
    "X-Seq-ApiKey" = $env:SEQ_TOKEN
    "Content-Type" = "application/json"
}

# Define custom time range
$fromTime = (Get-Date "2026-02-17 08:00:00").ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$toTime = (Get-Date "2026-02-17 12:00:00").ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$uri = "https://supportcs.citruslime.com/api/events?fromDateUtc=$fromTime&toDateUtc=$toTime&count=100"
$events = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

Write-Host "Events from $fromTime to $toTime: $($events.Count)" -ForegroundColor Cyan
```

## SEQ Filter Syntax

### Common Filter Patterns
```
# By level
@Level = 'Error'
@Level = 'Warning' or @Level = 'Error'

# By EventType (message template hash)
# EventType is returned by API as '$XXXXXXXX' but filter uses hex format 0xXXXXXXXX
@EventType = 0xA89EAC7E
@EventType = 0x564C0704

# By text search
@Message like '%exception%'
@Message like '%checkout%'

# By property
PropertyName = 'value'
PropertyName = 123
PropertyName <> null

# Combined filters
@Level = 'Error' and RepeaterID = 1
@Level = 'Error' and @Message like '%NullReference%'
@Level = 'Error' and @EventType = 0xA89EAC7E
```

### Log Levels
- `Verbose` - Detailed trace information
- `Debug` - Debugging information
- `Information` - General informational messages
- `Warning` - Warning messages
- `Error` - Error messages
- `Fatal` - Critical failures

## Helper Functions

### Reusable SEQ Query Function
```powershell
function Get-SeqEvents {
    param(
        [string]$SeqUrl = "https://supportcs.citruslime.com",
        [string]$Level = $null,
        [int]$Hours = 12,
        [int]$Count = 100,
        [string]$CustomFilter = $null
    )
    
    $headers = @{
        "X-Seq-ApiKey" = $env:SEQ_TOKEN
        "Content-Type" = "application/json"
    }
    
    $fromTime = (Get-Date).AddHours(-$Hours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Build filter
    if ($CustomFilter) {
        $filter = $CustomFilter
    } elseif ($Level) {
        $filter = "@Level = '$Level'"
    } else {
        $filter = $null
    }
    
    $uri = "$SeqUrl/api/events?count=$Count&fromDateUtc=$fromTime"
    if ($filter) {
        $uri += "&filter=$([uri]::EscapeDataString($filter))"
    }
    
    Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}

# Usage examples:
# Get-SeqEvents -Level Error -Hours 24
# Get-SeqEvents -CustomFilter "@Level = 'Error' and RepeaterID = 1"
```

### Group Events by Template with Counts
```powershell
function Get-SeqEventsByTemplate {
    param(
        [string]$Level = "Error",
        [int]$Hours = 12,
        [int]$TopN = 20
    )
    
    $events = Get-SeqEvents -Level $Level -Hours $Hours -Count 100
    
    $grouped = $events | Group-Object -Property EventType | Sort-Object Count -Descending | Select-Object -First $TopN
    
    $grouped | ForEach-Object {
        $sample = $_.Group[0]
        $messageTemplate = ($sample.MessageTemplateTokens | ForEach-Object { 
            $_.Text + $(if ($_.PropertyName) { "{$($_.PropertyName)}" }) 
        }) -join ''
        
        [PSCustomObject]@{
            EventType = $_.Name
            Count = $_.Count
            MessageTemplate = $messageTemplate
            LastSeen = $sample.Timestamp
        }
    }
}

# Usage:
# Get-SeqEventsByTemplate -Level Error -Hours 12 -TopN 20 | Format-Table -AutoSize -Wrap
```

## Tips and Best Practices

1. **Time Ranges**: Always specify time ranges to limit query scope and improve performance
2. **Count Limits**: The API has a default limit; use `count` parameter to control batch size
3. **Event Grouping**: Group by `EventType` to identify recurring issues
4. **Property Filtering**: Filter by properties to narrow down specific error instances
5. **Performance**: Large queries can be slow; start with smaller time ranges
6. **Multiple Instances**: Use different environment variables for multiple SEQ instances

## Useful Queries

### Find Most Common Errors (Last 24 Hours)
```powershell
Get-SeqEventsByTemplate -Level Error -Hours 24 -TopN 10
```

### Find Specific Exception Type
```powershell
Get-SeqEvents -CustomFilter "@Level = 'Error' and @Exception like '%NullReferenceException%'" -Hours 24
```

### Monitor Recent Critical Issues
```powershell
Get-SeqEvents -Level Fatal -Hours 1 | Format-List
```

### Check Application Health (Warnings + Errors)
```powershell
Get-SeqEvents -CustomFilter "@Level = 'Warning' or @Level = 'Error'" -Hours 1 -Count 50
```

## API Documentation
Full SEQ API documentation: https://docs.datalust.co/docs/using-the-http-api

## Security Notes
- Never commit `.env` files to version control
- Keep API tokens secure and rotate them regularly
- Use environment variables for sensitive data
- The `SEQ_TOKEN` is loaded from `.env` using `Load-Env.ps1`
- API keys can have read-only or read-write permissions - use read-only for querying

## Troubleshooting

### No Events Returned
- Check your API token is valid
- Verify the time range (events might be outside the range)
- Check filter syntax
- Ensure you have permissions to access the SEQ instance

### Slow Queries
- Reduce the time range
- Reduce the count parameter
- Add more specific filters
- Consider using SEQ signals for aggregated data

### Filter Not Working
- Verify filter syntax (case-sensitive)
- Ensure property names match exactly
- Use URL encoding for special characters
- Test filters in SEQ web UI first
