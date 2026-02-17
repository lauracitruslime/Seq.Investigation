# Jira API Integration Skill

## Description
This skill enables interaction with Jira (Atlassian) using PowerShell and the Jira REST API v3. It provides methods to search, read, create, and update Jira issues programmatically.

## Prerequisites
- PowerShell 7+
- Jira Cloud account with API token
- Environment variables configured in `.env` file

## Setup

### 1. Environment Variables
Ensure your `.env` file contains the Jira API token:
```
JIRA_TOKEN="your-jira-api-token-here"
```

### 2. Load Environment Variables
Before using Jira commands, load the environment variables:
```powershell
. .\Load-Env.ps1
```

This will load the `JIRA_TOKEN` and other environment variables for the current session.

### 3. Configuration
Set these variables for your Jira instance:
- **Jira URL**: `https://citruslime.atlassian.net`
- **Email**: `laura@citruslime.com` (use git config user.email)
- **Project Key**: `CLECOM` (or any project you have access to)

## Authentication
Jira Cloud API uses Basic Authentication with email and API token:
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}
```

## Common Operations

### Search for Issues
Search issues using JQL (Jira Query Language):
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}
$body = @{
    jql = "project=CLECOM ORDER BY created DESC"
    maxResults = 10
    fields = @("summary", "status", "assignee", "created", "issuetype", "priority")
} | ConvertTo-Json

$result = Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/search/jql" -Headers $headers -Method Post -Body $body

# Format results
$result.issues | ForEach-Object {
    [PSCustomObject]@{
        Key = $_.key
        Summary = $_.fields.summary
        Status = $_.fields.status.name
        Type = $_.fields.issuetype.name
        Priority = $_.fields.priority.name
        Created = $_.fields.created
    }
} | Format-Table -AutoSize
```

### Get a Specific Issue
Retrieve detailed information about an issue:
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}

$issue = Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue/CLECOM-11224" -Headers $headers -Method Get

# Display issue details
[PSCustomObject]@{
    Key = $issue.key
    Summary = $issue.fields.summary
    Description = if ($issue.fields.description) { $issue.fields.description.content[0].content[0].text } else { "No description" }
    Status = $issue.fields.status.name
    Priority = $issue.fields.priority.name
    Type = $issue.fields.issuetype.name
    Assignee = if ($issue.fields.assignee) { $issue.fields.assignee.displayName } else { "Unassigned" }
    Reporter = $issue.fields.reporter.displayName
    Created = $issue.fields.created
    Updated = $issue.fields.updated
} | Format-List
```

### Create a New Issue
Create a new Jira issue:
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}

$newIssue = @{
    fields = @{
        project = @{
            key = "CLECOM"
        }
        summary = "Your issue summary here"
        description = @{
            type = "doc"
            version = 1
            content = @(
                @{
                    type = "paragraph"
                    content = @(
                        @{
                            type = "text"
                            text = "Detailed description of the issue."
                        }
                    )
                }
            )
        }
        issuetype = @{
            name = "Task"  # Can be: Task, Bug, Story, Epic, etc.
        }
    }
} | ConvertTo-Json -Depth 10

$created = Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue" -Headers $headers -Method Post -Body $newIssue
Write-Host "✓ Created issue: $($created.key)" -ForegroundColor Green
Write-Host "  URL: https://citruslime.atlassian.net/browse/$($created.key)" -ForegroundColor Cyan
```

### Update an Issue
Update an existing issue:
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}

$update = @{
    fields = @{
        summary = "Updated summary"
        description = @{
            type = "doc"
            version = 1
            content = @(
                @{
                    type = "paragraph"
                    content = @(
                        @{
                            type = "text"
                            text = "Updated description."
                        }
                    )
                }
            )
        }
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue/CLECOM-12345" -Headers $headers -Method Put -Body $update
Write-Host "✓ Updated issue" -ForegroundColor Green
```

### Add a Comment
Add a comment to an issue:
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}

$comment = @{
    body = @{
        type = "doc"
        version = 1
        content = @(
            @{
                type = "paragraph"
                content = @(
                    @{
                        type = "text"
                        text = "Your comment here."
                    }
                )
            }
        )
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue/CLECOM-12345/comment" -Headers $headers -Method Post -Body $comment
Write-Host "✓ Comment added" -ForegroundColor Green
```

### Transition Issue Status
Change the status of an issue (e.g., To Do → In Progress → Done):
```powershell
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
    "Content-Type" = "application/json"
}

# First, get available transitions for the issue
$transitions = Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue/CLECOM-12345/transitions" -Headers $headers -Method Get
$transitions.transitions | Select-Object id, name | Format-Table

# Then apply a transition (use the transition ID from above)
$transition = @{
    transition = @{
        id = "31"  # Replace with actual transition ID
    }
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://citruslime.atlassian.net/rest/api/3/issue/CLECOM-12345/transitions" -Headers $headers -Method Post -Body $transition
Write-Host "✓ Issue status updated" -ForegroundColor Green
```

## Useful JQL Queries

### Find Your Assigned Issues
```jql
assignee = currentUser() AND status != Done ORDER BY priority DESC
```

### Find Recently Updated Issues
```jql
project = CLECOM AND updated >= -7d ORDER BY updated DESC
```

### Find Bugs in To Do Status
```jql
project = CLECOM AND issuetype = Bug AND status = "To Do" ORDER BY priority DESC
```

### Find Issues by Text
```jql
project = CLECOM AND text ~ "activation" ORDER BY created DESC
```

## Tips and Best Practices

1. **Reusable Headers**: Store the auth headers in a variable to avoid repetition
2. **Error Handling**: Wrap API calls in try-catch blocks for production use
3. **Rate Limits**: Be aware of Jira API rate limits (approximately 100 requests per minute)
4. **Field IDs**: Some custom fields use IDs like `customfield_10001` - check your Jira field configuration
5. **Pagination**: Use `startAt` parameter for large result sets

## Helper Function
Create a reusable function for API calls:
```powershell
function Invoke-JiraApi {
    param(
        [string]$Endpoint,
        [string]$Method = "Get",
        [object]$Body = $null
    )
    
    $headers = @{
        "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("laura@citruslime.com:$env:JIRA_TOKEN"))
        "Content-Type" = "application/json"
    }
    
    $params = @{
        Uri = "https://citruslime.atlassian.net/rest/api/3/$Endpoint"
        Headers = $headers
        Method = $Method
    }
    
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }
    
    Invoke-RestMethod @params
}

# Usage example:
# Invoke-JiraApi -Endpoint "issue/CLECOM-12345" -Method Get
```

## API Documentation
Full Jira REST API documentation: https://developer.atlassian.com/cloud/jira/platform/rest/v3/

## Security Notes
- Never commit `.env` files to version control
- Keep API tokens secure and rotate them regularly
- Use environment variables for sensitive data
- The `JIRA_TOKEN` is loaded from `.env` using `Load-Env.ps1`
