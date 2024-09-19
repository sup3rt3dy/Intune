#Disclaimer:
#This script is provided "as is" without any guarantees or warranties. I am not responsible for any damage, data loss, 
#or issues that may arise from using this script. You are using it at your own risk. Always review and understand any 
#script before running it on your system. Ensure you have appropriate backups and safeguards in place.

# Install the Microsoft.Graph module if not already installed
Install-Module -Name Microsoft.Graph -Force -Scope CurrentUser

# Import the module
Import-Module Microsoft.Graph.Groups
# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"

# Get all managed devices
$groupId = "[xxxxxxx]" #set group id
$devices = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/devicemanagement/manageddevices?`$filter=contains(operatingSystem,'Windows')").value

# Filter devices that are managed only by Intune and are not compliant
$nonCompliantDevices = $devices | Where-Object { $_.ManagementAgent -eq 'mdm' -and $_.ComplianceState -ne 'compliant' }

# Output the azureId of non-compliant devices
foreach($nonCompliantDevice in $nonCompliantDevices)
        {   $azureId = $nonCompliantDevice.AzureAdDeviceId
            $objectIds = (Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$($azureId)'").value
        }

# Get current members of the test group
$currentGroupMembers = Get-MgGroupMember -GroupId $groupId | Select-Object -ExpandProperty Id

# Add non-compliant devices to the test group
foreach ($objectId in $objectIds) {
    if ($currentGroupMembers -notcontains $objectId) {
        New-MgGroupMember -GroupId $groupId -DirectoryObjectId $objectId.id
    }
}

# Remove devices from the test group that are compliant
foreach ($memberId in $currentGroupMembers) {
    if ($azureIds -notcontains $memberId) {
        Remove-MgGroupMemberByRef -GroupId $groupId -MemberId $memberId.ObjectId
    }
}

Write-Output "Group for non compliant devices has been updated."