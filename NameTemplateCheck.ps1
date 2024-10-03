#Disclaimer:
#This script is provided "as is" without any guarantees or warranties. I am not responsible for any damage, data loss, 
#or issues that may arise from using this script. You are using it at your own risk. Always review and understand any 
#script before running it on your system. Ensure you have appropriate backups and safeguards in place.

# Set this variable to $true for test mode or $false for live execution
$TestMode = $true  # Set to $false for actual renaming

$ApplicationId = "<value>"
$SecuredPassword = "<value>"
$tenantID = "<value>"

$SecuredPasswordPassword = ConvertTo-SecureString -String $SecuredPassword -AsPlainText -Force

$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPasswordPassword

Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential

#set size of your Naming Template prefix
$templatePrefixSize = "4"

#set your pc manufacturer
$manufacturer = "Lenovo"

# Fetch all Windows Autopilot deployment profiles
$profiles = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles").value

# Loop through each profile to check device namesW
foreach ($profile in $profiles) {
    # Get the device name template for this profile and check if it's null or empty
    $deviceNameTemplate = $profile.deviceNameTemplate
    
    if (-not $deviceNameTemplate) {
        Write-Host "Profile $($profile.displayName) does not have a deviceNameTemplate set. Skipping..."
        continue
    }

    # Ensure the deviceNameTemplate is at least 4 characters long before taking a substring
    if ($deviceNameTemplate.Length -lt $templatePrefixSize) {
        Write-Host "Device name template is shorter than $templatePrefixSize characters for profile $($profile.displayName). Skipping..."
        continue
    }

    # Extract the first 4 characters of the deviceNameTemplate
    $templatePrefix = $deviceNameTemplate.Substring(0, $templatePrefixSize)
    Write-Host "Checking profile $($profile.displayName) with template prefix: $templatePrefix"

    # Fetch the devices assigned to the current deployment profile
    $profileId = $profile.id
    $assignedDevicesUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$profileId/assignedDevices"
    $assignedDevicesBF = (Invoke-MgGraphRequest -Method GET -Uri $assignedDevicesUri).value
    #Filter Out unwated devices (in this case devices that are alive in intune)
    $assignedDevices = $assignedDevicesBF | Where-Object { $_.Manufacturer -eq $manufacturer -and $_.ManagedDeviceId -ne $null -and $_.ManagedDeviceId -ne '00000000-0000-0000-0000-000000000000' -and $_.lastContactedDateTime -ne '01/01/0001 00:00:00'}

    foreach ($device in $assignedDevices) {
        
        # Fetch detailed info for each device
        $deviceId = $device.azureAdDeviceId
        $deviceDetails = (Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/devicemanagement/manageddevices?`$filter=azureADDeviceId eq '$($deviceId)'").value
        $ManagedDID = $device.ManagedDeviceId

        # Get the device's current name and ensure it's not null or empty
        $currentDeviceName = $deviceDetails.deviceName

        # Check if the current device name matches the first 4 characters of the template
        if ($currentDeviceName.Substring(0, 4) -ne $templatePrefix) {
            Write-Host "Device $($deviceDetails.serialNumber) has name $currentDeviceName which does not match the template."

            # Construct the new device name based on the template
            $newDeviceName = $deviceNameTemplate.Replace("%SERIAL%", $deviceDetails.serialNumber)

            if ($TestMode) {
                # In test mode, just print what would be done
                Write-Host "[TEST MODE] Would rename device $($deviceDetails.serialNumber) from $currentDeviceName to $newDeviceName"
            } else {
                # In live mode, perform the actual renaming
                Write-Host "Renaming device $($deviceDetails.serialNumber) from $currentDeviceName to $newDeviceName..."

                # Rename the device (This part assumes you have the required permissions to rename devices)$ManagedDID
                $renameUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$ManagedDID/setDeviceName"
                
                $body = @{
                    "newDeviceName" = $newDeviceName
                } | ConvertTo-Json

                Invoke-MgGraphRequest -Method POST -Uri $renameUri -Body $body -ContentType "application/json"
                Write-Host "Renamed device $($deviceDetails.serialNumber) to $newDeviceName"
            }
        } 
        else {
            Write-Host "Device $($deviceDetails.serialNumber) name is already in accordance with the template."
        }
    }
}

Write-Host "Script completed. Test Mode: $TestMode"

Disconnect-MgGraph