Param(
    [string]$TenantId = '[fill out]',
    [string]$ClientId = '[fill out]',
    [string]$ClientSecret = '[fill out]'
)

Add-Type -AssemblyName System.Windows.Forms

# Get Access Token
$Body = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret&scope=https://graph.microsoft.com/.default"
$Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
$TokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $Body -Headers $Headers -ContentType "application/x-www-form-urlencoded"
$AccessToken = $TokenResponse.access_token

# Save original power settings
$OriginalACSetting = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE).Split()[-1]
$OriginalDCSetting = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE).Split()[-1]

# Function to prevent sleep
function Prevent-Sleep {
    Write-Host "Disabling sleep mode..."
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
}

# Function to restore original sleep settings
function Restore-Sleep {
    Write-Host "Restoring original sleep settings..."
    powercfg /change standby-timeout-ac $OriginalACSetting
    powercfg /change standby-timeout-dc $OriginalDCSetting
}

# Create GUI
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Intune Device Compliance"
$Form.Size = New-Object System.Drawing.Size(750, 400)
$Form.StartPosition = "CenterScreen"

# Label
$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Enter Device Name:"
$Label.Location = New-Object System.Drawing.Point(10, 20)
$Label.AutoSize = $true
$Label.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($Label)

# TextBox for Device Name
$TextBoxInput = New-Object System.Windows.Forms.TextBox
$TextBoxInput.Location = New-Object System.Drawing.Point(200, 15)
$TextBoxInput.Size = New-Object System.Drawing.Size(400, 30)
$TextBoxInput.Font = New-Object System.Drawing.Font("Arial", 12)
$currentHostname = $env:COMPUTERNAME
$TextBoxInput.Text = $currentHostname  # Pre-fill with current hostname
$Form.Controls.Add($TextBoxInput)

# Compliance Button
$Button = New-Object System.Windows.Forms.Button
$Button.Text = "Get Compliance Info"
$Button.Location = New-Object System.Drawing.Point(200, 55)
$Button.Size = New-Object System.Drawing.Size(200, 35)
$Button.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($Button)

# Cancel Button
$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Text = "Cancel Sync"
$CancelButton.Location = New-Object System.Drawing.Point(420, 55)
$CancelButton.Size = New-Object System.Drawing.Size(180, 35)
$CancelButton.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($CancelButton)

# Output TextBox
$TextBoxOutput = New-Object System.Windows.Forms.TextBox
$TextBoxOutput.Location = New-Object System.Drawing.Point(10, 100)
$TextBoxOutput.Size = New-Object System.Drawing.Size(710, 200)
$TextBoxOutput.Multiline = $true
$TextBoxOutput.Font = New-Object System.Drawing.Font("Arial", 10)
$TextBoxOutput.ScrollBars = "Vertical"
$Form.Controls.Add($TextBoxOutput)

# Sync Control Variables
$SyncCancel = $false
$LastSyncTime = ""

# Function to Check Compliance
function Get-ComplianceStatus {
    param($DeviceName)
    $GraphUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$DeviceName'&`$select=id,deviceName,operatingSystem,complianceState,managementAgent"
    $Headers = @{ "Authorization" = "Bearer $AccessToken" }
    $Device = Invoke-RestMethod -Uri $GraphUri -Headers $Headers -Method Get

    if ($Device.value.Count -gt 0) {
        return $Device.value[0]
    } else {
        return $null
    }
}

# Compliance Button Click Event
$Button.Add_Click({
    $DeviceName = $TextBoxInput.Text
    if ($DeviceName) {
        $SelectedDevice = Get-ComplianceStatus -DeviceName $DeviceName
        if ($SelectedDevice) {
            $TextBoxOutput.Text = "Device: $($SelectedDevice.deviceName)`r`nOS: $($SelectedDevice.operatingSystem)`r`nCompliance: $($SelectedDevice.complianceState)`r`nManagement Agent: $($SelectedDevice.managementAgent)"
            
            if ($SelectedDevice.complianceState -ne "compliant") {
                Prevent-Sleep  # Prevent sleep while syncing
                $LastSyncTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                while ($true) {
                    if ($SyncCancel) {
                        $TextBoxOutput.Text += "`r`nSync canceled."
                        Restore-Sleep  # Restore sleep settings on cancel
                        break
                    }
                    
                    Start-Process -FilePath "C:\Program Files (x86)\Microsoft Intune Management Extension\Microsoft.Management.Services.IntuneWindowsAgent.exe" -ArgumentList "intunemanagementextension://synccompliance" -NoNewWindow -Wait
                    $TextBoxOutput.Text += "`r`nCompliance sync initiated at $LastSyncTime. Waiting 5 minutes..."
                    Start-Sleep -Seconds 300
                    $SelectedDevice = Get-ComplianceStatus -DeviceName $DeviceName
                    if ($SelectedDevice.complianceState -eq "compliant") {
                        $TextBoxOutput.Text += "`r`nDevice is now compliant!"
                        Restore-Sleep  # Restore sleep settings after successful sync
                        break
                    }
                }
            }
        } else {
            $TextBoxOutput.Text = "No data available for $DeviceName."
        }
    } else {
        $TextBoxOutput.Text = "Please enter a device name."
    }
})

# Cancel Button Click Event
$CancelButton.Add_Click({
    $SyncCancel = $true
    $TextBoxOutput.Text += "`r`nSync cancellation requested."
    Restore-Sleep  # Ensure power settings are restored
})

# Restore power settings when closing the program
$Form.Add_FormClosing({
    Restore-Sleep
})

$Form.ShowDialog()