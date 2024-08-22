Function Add-IntuneWin32AppScopeTag {
    <#
    .SYNOPSIS
    Add a scope tag to a Win32 app.

    .DESCRIPTION
    Add a scope tag to a Win32 app.

    .PARAMETER ID
    Specify the ID for a Win32 application.

    .PARAMETER ScopeTagID
    Specify the ID for a scope tag.        

    .PARAMETER RemoveDefault
    Specify the filter mode of the specified Filter, e.g. Include or Exclude.

    .NOTES
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2024-08-20
    Updated:     2024-08-20

    Version history:
    1.0.0 - (2024-08-20) Function created
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = "ID", HelpMessage = "Specify the ID for an application.")]
        [ValidatePattern("^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$")]
        [ValidateNotNullOrEmpty()]
        [string]$ID,

        [parameter(Mandatory = $true, ParameterSetName = "ID", HelpMessage = "Specify the ID of the RBAC Scopetag.")]
        [ValidatePattern("^\d+$")]
        [ValidateNotNullOrEmpty()]
        [string]$ScopeTagID,

        [parameter(Mandatory = $false, HelpMessage = "Remove the default scope tag (ID 0).")]
        [bool]$RemoveDefault = $false
    )
    Begin {
        # Ensure required authentication header variable exists
        if ($Global:AuthenticationHeader -eq $null) {
            Write-Warning -Message "Authentication token was not found, use Connect-MSIntuneGraph before using this function"; break
        }
        else {
            $TokenLifeTime = ($Global:AuthenticationHeader.ExpiresOn - (Get-Date).ToUniversalTime()).Minutes
            if ($TokenLifeTime -le 0) {
                Write-Warning -Message "Existing token found but has expired, use Connect-MSIntuneGraph to request a new authentication token"; break
            }
            else {
                Write-Verbose -Message "Current authentication token expires in (minutes): $($TokenLifeTime)"
            }
        }

        # Set script variable for error action preference
        $ErrorActionPreference = "Stop"
    }
    Process {
        # Retrieve Win32 app by ID from parameter input
        Write-Verbose -Message "Querying for Win32 app using ID: $($ID)"       
        $Win32App = Invoke-IntuneGraphRequest -APIVersion "Beta" -Resource "mobileApps/$($ID)" -Method "GET"
        if ($Win32App -ne $null) {
            $Win32AppID = $Win32App.id
            $roleScopeTagIds = @($Win32App.roleScopeTagIds)
            $UpdateRequired = $false
            $DuplicateScopeTag = $false

            # Add the new ScopeTag if not already present
            if (-Not($roleScopeTagIds -contains $ScopeTagID)) {
                $roleScopeTagIds += $ScopeTagID
                $UpdateRequired = $true
            }
            else {
                $DuplicateScopeTag = $true
            }
			
            # Remove default scope tag (ID 0) if -RemoveDefault is specified and there's at least one other scope tag
            if ($PSBoundParameters["RemoveDefault"] -and ($roleScopeTagIds.Count -gt 1)) {
                if ($roleScopeTagIds -contains '0') {
                    $roleScopeTagIds = $roleScopeTagIds | Where-Object { $_ -ne '0' }
                    Write-Verbose "Removed default scope tag (ID 0) from scope tags."
                    $UpdateRequired = $true
                } 
                else {
                    Write-Verbose "Default scope tag (ID 0) was not present, no removal needed."
                }
            }

            # Only update if there is at least one scope tag left
            if ($roleScopeTagIds.Count -gt 0 -and $UpdateRequired) {
                $Global:Wn32AppScopeTagTable = [ordered]@{
                    '@odata.type'     = $Win32App.'@odata.type'
                    'roleScopeTagIds' = @($roleScopeTagIds)
                }
				
                Try {
                    # Attempt to call Graph and create new assignment for Win32 app
                    Invoke-IntuneGraphRequest -APIVersion "Beta" -Resource "mobileApps/$($Win32AppID)" -Method "PATCH" -Body ($Wn32AppScopeTagTable | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-Warning -Message "An error occurred while updating a Win32 app scopetag. Error message: $($_.Exception.Message)"
                }
            } 
            else {
                if ($DuplicateScopeTag -eq $true -and $UpdateRequired -eq $false) {
                    Write-Verbose "Scope Tag '$ScopeTagID' is already assigned to the application. No changes made."
                } 
                else {
                    Write-Warning "No scope tags remaining after attempting to remove the default scope tag (ID 0). The operation was not performed."
                }
            }     
        }
        else {
            Write-Warning -Message "Query for Win32 app returned an empty result, no apps matching the specified search criteria with ID '$($ID)' was found"
        }
    }
}