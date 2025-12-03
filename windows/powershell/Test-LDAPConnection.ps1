# LDAP Connection Test Tool

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LDAP Connection Test Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# User input parameters
$server = Read-Host "`nEnter LDAP Server IP"
$port = Read-Host "Enter Port (default 389, GC use 3268)"
if ([string]::IsNullOrWhiteSpace($port)) { $port = "389" }

$username = Read-Host "Enter Username (e.g., dev\hank_lin or user@domain.com)"
$pwd = Read-Host "Enter Password" -AsSecureString
$pwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd))

$searchBase = Read-Host "Enter Search Base (e.g., DC=dev,DC=gss)"

$ldapPath = "LDAP://${server}:${port}"

Write-Host "`nStarting connection test..." -ForegroundColor Yellow
Write-Host "Server: $server" -ForegroundColor Gray
Write-Host "Port: $port" -ForegroundColor Gray
Write-Host "Username: $username" -ForegroundColor Gray
Write-Host "Base DN: $searchBase" -ForegroundColor Gray

$connectionSuccess = $false
$querySuccess = $false

try {
    $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $username, $pwd)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($de)
    $searcher.Filter = "(objectClass=*)"
    $searcher.SearchScope = "Base"
    $result = $searcher.FindOne()

    if ($result -ne $null) {
        Write-Host "`n✓✓✓ Connection successful!✓✓✓" -ForegroundColor Green
        Write-Host "Path: $ldapPath" -ForegroundColor Yellow
        $connectionSuccess = $true
    } else {
        Write-Host "`n✗ No results" -ForegroundColor Red
    }
    
} catch {
    Write-Host "`n✗ Connection failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    exit
}

if ($connectionSuccess) {
    Write-Host "`n========================================"  -ForegroundColor Cyan
    Write-Host "✓ Connection verification successful" -ForegroundColor Green
    Write-Host "========================================"  -ForegroundColor Cyan
    Write-Host "Using account: $username" -ForegroundColor Yellow
        
    # Additional test
    Write-Host "`n[Additional Test] Querying users..." -ForegroundColor Yellow
    try {
        $ldapPathWithBase = "LDAP://${server}:${port}/${searchBase}"
        $de = New-Object System.DirectoryServices.DirectoryEntry(
            $ldapPathWithBase,
            $username,
            $pwd
        )
            
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($de)
        $searcher.Filter = "(&(objectClass=user)(objectCategory=person))"
        $searcher.PropertiesToLoad.Add("cn") | Out-Null
        $searcher.PropertiesToLoad.Add("sAMAccountName") | Out-Null
        $searcher.SizeLimit = 3
            
        $results = $searcher.FindAll()
            
        if ($results.Count -gt 0) {
            Write-Host "✓ Successfully queried $($results.Count) users" -ForegroundColor Green
            $querySuccess = $true
            foreach ($user in $results) {
                $cn = $user.Properties["cn"][0]
                $sam = if ($user.Properties["sAMAccountName"].Count -gt 0) { 
                    $user.Properties["sAMAccountName"][0] 
                } else { 
                    "N/A" 
                }
                Write-Host "  - $cn ($sam)" -ForegroundColor Gray
            }
        } else {
            Write-Host "⚠ No users found" -ForegroundColor Yellow
            Write-Host "  Possible reasons:" -ForegroundColor Gray
            Write-Host "  1. Incorrect Search Base configuration" -ForegroundColor Gray
            Write-Host "  2. No users under this OU" -ForegroundColor Gray
            Write-Host "  3. Account lacks query permissions for this OU" -ForegroundColor Gray
        }
    } catch {
        Write-Host "✗ Query failed" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "`nPossible reasons:" -ForegroundColor Gray
        Write-Host "  1. Incorrect Search Base (DC) configuration" -ForegroundColor Gray
        Write-Host "  2. Account lacks query permissions" -ForegroundColor Gray
        Write-Host "  3. Path does not exist" -ForegroundColor Gray
        Write-Host "`nSuggestions:" -ForegroundColor Yellow
        Write-Host "  - Check if Search Base is correct: $searchBase" -ForegroundColor Gray
        Write-Host "  - Try using a higher level DC (e.g., DC=gss)" -ForegroundColor Gray
    }
}
    
# Display recommended Java configuration
Write-Host "`n========================================"  -ForegroundColor Cyan
Write-Host "Recommended Java LDAP Configuration:" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "ldapUrl = `"ldap://${server}:${port}`"" -ForegroundColor Yellow

if ($querySuccess) {
    Write-Host "baseDn = `"$searchBase`"" -ForegroundColor Yellow
} else {
    Write-Host "baseDn = `"(Query failed, please check Search Base configuration)`"" -ForegroundColor Red
}

Write-Host "bindDn = `"$username`"" -ForegroundColor Yellow
Write-Host "password = `"********`"" -ForegroundColor Yellow

Write-Host "`nTest completed!" -ForegroundColor Cyan