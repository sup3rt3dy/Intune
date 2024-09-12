#script should be run in user context

#rev 1
# added start process Company portal, so that on the next check there should be some files present

# Function to retrieve the compliance state from Company Portal cache files
function Get-IntuneComplianceFromCache {
    Write-Host "Checking Intune compliance status from Company Portal cache..."

    # Define the path to the Company Portal cache
    $cachePath = Join-Path $env:LOCALAPPDATA -ChildPath "Packages\Microsoft.CompanyPortal_8wekyb3d8bbwe\TempState\ApplicationCache"

    # Get all .tmp files from the cache, sorted by LastWriteTime (newest first)
    $tmpFiles = Get-ChildItem -Path $cachePath -Include *.tmp* -File -Recurse -ErrorAction SilentlyContinue | Sort-Object -Descending -Property LastWriteTime

    if ($tmpFiles -and $tmpFiles.Count -gt 0) {
        # Loop through each file to find the ComplianceState
        foreach ($file in $tmpFiles) {
            Write-Host "Checking file: $($file.FullName)"

            try {
                # Read the content of the file and attempt to parse it as JSON
                $fileContent = Get-Content -Path $file.FullName -Raw
                $jsonData = $fileContent | ConvertFrom-Json

                # Try to extract the compliance state from the JSON structure
                if ($jsonData -and $jsonData.data) {
                    $complianceState = ($jsonData.data | ConvertFrom-Json).ComplianceState

                    if ($complianceState) {
                        Write-Host "Compliance State found: $complianceState"

                        # If the compliance state is "Compliant", return 0
                        if ($complianceState -eq "Compliant") {
                            Write-Host "Device is compliant."
                            exit 0
                        } else {
                            Write-Host "Device is not compliant."
                            return $complianceState
                            Exit 1
                        }
                    }
                }
            } catch {
                Write-Host "Failed to read or parse the file: $($_.Exception.Message)"
                # Continue with the next file if this one fails
            }
        }

        Write-Host "No ComplianceState found in any of the files."
    } else {
        Write-Host "No .tmp files found in the Company Portal cache."
    }

    # Fallback: Launch the Company Portal app if no files or compliance state found
    Write-Host "Attempting to launch Company Portal to refresh compliance status..."
    try {
        Start-Process shell:AppsFolder\Microsoft.CompanyPortal_8wekyb3d8bbwe!App
        Write-Host "Company Portal launched successfully."
    } catch {
        Write-Host "Failed to launch Company Portal: $($_.Exception.Message)"
    }

    return $null
}

# Execute the function to check compliance
Get-IntuneComplianceFromCache
