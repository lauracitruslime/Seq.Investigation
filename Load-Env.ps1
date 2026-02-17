function Load-DotEnv {
    <#
    .SYNOPSIS
        Loads environment variables from a .env file
    .DESCRIPTION
        Reads a .env file and sets environment variables for the current session
    .PARAMETER Path
        Path to the .env file (defaults to .env in current directory)
    .EXAMPLE
        Load-DotEnv
        Load-DotEnv -Path "C:\path\to\.env"
    #>
    param(
        [string]$Path = ".env"
    )
    
    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return
    }
    
    Write-Host "Loading environment variables from: $Path" -ForegroundColor Cyan
    
    $loaded = 0
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            return
        }
        
        # Match KEY=VALUE pattern
        if ($line -match '^([^#][^=]*?)\s*=\s*(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove surrounding quotes if present
            $value = $value -replace '^["'']|["'']$'
            
            # Set environment variable
            Set-Item -Path "env:$name" -Value $value
            Write-Host "  ✓ $name" -ForegroundColor Green
            $loaded++
        }
    }
    
    Write-Host "Loaded $loaded environment variable(s)" -ForegroundColor Cyan
}

# Auto-load if .env exists in current directory
if (Test-Path ".env") {
    Load-DotEnv
}
