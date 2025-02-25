<#
_author_ = Texas Roemer <Texas_Roemer@Dell.com>
_version_ = 8.0

Copyright (c) 2020, Dell, Inc.

This software is licensed to you under the GNU General Public License,
version 2 (GPLv2). There is NO WARRANTY for this software, express or
implied, including the implied warranties of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
along with this software; if not, see
http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#>

<#
.Synopsis
   Cmdlet using Redfish DMTF action SimpleUpdate to update device firmware using a firmware image stored locally.
.DESCRIPTION
   Cmdlet used to update firmware for one supported server device which uses a local image file. For updating devices, you will be using Dell Windows Update Packages (DUP) with .EXE extension. NOTE: If executing cmdlet on iDRAC 7/8, to download the firmware image, curl command will be used. If using iDRAC 9 or newer, Invoke-WebRequest command will be used. NOTE: Curl command is natively installed in newer versions of Windows (Examples: Windows 10 or Windows Server 2019). If using older version of Windows with iDRAC 7/8, please install curl command before executing the cmdlet. 

   Supported parameters to pass in for cmdlet:
   
   - idrac_ip: Pass in iDRAC IP
   - idrac_username: Pass in iDRAC username
   - idrac_password: Pass in iDRAC password
   - image_directory_path: Pass in the directory path where the upload image is. Example: "C:\firmware_directory"
   - image_filename: Pass in the name of the upload image. Example: "H330_SAS-RAID_Firmware_03NXN_WN64_25.5.2.0001_A07.EXE"
   - reboot_server: Pass in "y" to automatically reboot the server to apply the update or "n" to not reboot the server. Passing in "n" means the update job will still get scheduled and will execute on next server manual reboot. NOTE: There are devices which perform an update immediately and devices that need a reboot to apply the update. For more details on this behavior, refer to Lifecycle Controller User Guide update section.
   - view_fw_inventory_only: this will return only the firmware inventory of devices on the system iDRAC supports for updates.

.EXAMPLE
   Set-DeviceFirmwareSimpleUpdateREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -view_fw_inventory_only y 
   # This example will only return Firmware inventory for all devices in the server. If needed, you can redirect output into a variable allowing you to get only specific properties.
.EXAMPLE
   Set-DeviceFirmwareSimpleUpdateREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -image_directory_path C:\Downloads -image_filename BIOS_8G2RV_WN64_2.4.8.EXE -reboot_server y
   # This example will download BIOS firmware and reboot the server now to perform the update 
.EXAMPLE
   Set-DeviceFirmwareSimpleUpdateREDFISH.ps1 -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -image_directory_path C:\Downloads -image_filename iDRAC-with-Lifecycle-Controller_Firmware_4JCPK_WN64_4.00.00.00_A00.EXE
   # This example will update iDRAC firmware and get applied immediately. Since this device gets update immediately, no server reboot is needed.
.EXAMPLE
   Set-DeviceFirmwareSimpleUpdateREDFISH -idrac_ip 192.168.0.120 -idrac_username root -idrac_password calvin -image_directory_path C:\Downloads -image_filename BIOS_8G2RV_WN64_2.4.8.EXE -reboot_server n
   # This example will download BIOS firmware and NOT reboot the server to apply the update. The update job will still get scheduled and will execute on next manual server reboot.
#>

function Set-DeviceFirmwareSimpleUpdateREDFISH {

# Required, optional parameters needed to be passed in when cmdlet is executed

param(
    [Parameter(Mandatory=$True)]
    [string]$idrac_ip,
    [Parameter(Mandatory=$True)]
    [string]$idrac_username,
    [Parameter(Mandatory=$True)]
    [string]$idrac_password,
    [Parameter(Mandatory=$False)]
    [string]$image_directory_path,
    [Parameter(Mandatory=$False)]
    [string]$image_filename,
    [Parameter(Mandatory=$False)]
    [string]$reboot_server,
    [Parameter(Mandatory=$False)]
    [string]$view_fw_inventory_only
    )


# Function to ignore SSL certs

function Ignore-SSLCertificates
{
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

# Function to set up iDRAC credentials 

function setup_idrac_creds
{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12
#[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
$user = $idrac_username
$pass= $idrac_password
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$global:credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
}

$global:get_powershell_version = $null

function get_powershell_version 
{
$get_host_info = Get-Host
$major_number = $get_host_info.Version.Major
$global:get_powershell_version = $major_number
}

get_powershell_version


# Function get current firmware versions

function get_firmware_versions
{
Write-Host
Write-Host "--- Getting Firmware Inventory For iDRAC $idrac_ip ---"
Write-Host

$expand_query ='?$expand=*($levels=1)'
$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory$expand_query"
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    }
    $get_fw_inventory = $result.Content | ConvertFrom-Json
    $get_fw_inventory.Members
    return
}

# Function download image payload

function download_image_payload
{

$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory"
try
{
if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -Uri $uri -Credential $credential -Method Get -UseBasicParsing -Headers @{"Accept"="application/json"} -SkipHeaderValidation
    $ETag=[string]$get_result.Headers.ETag
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    $ETag=$get_result.Headers.ETag
    }
}
catch
{
Write-Host
$RespErr
break
}

$uri = "https://$idrac_ip/redfish/v1/Managers/iDRAC.Embedded.1"
try
{
if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -Uri $uri -Credential $credential -Method Get -UseBasicParsing -Headers @{"Accept"="application/json"} -SkipHeaderValidation
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
}
catch
{
Write-Host
$RespErr
break
}

$get_content = $result.Content | ConvertFrom-Json
if ($get_content.Model.Contains("12G") -or $get_content.Model.Contains("13G"))
{

Write-Host "`n- INFO, downloading firmware image using iDRAC7/8, this may take a few minutes depending of the size of the image.`n"

$FilePath = $image_directory_path + "\" + $image_filename
$CurlExecutable = "curl.exe"
$idrac_username_password = $idrac_username+":"+$idrac_password 
$execute_post_output = & $CurlExecutable --request POST https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory --header "If-Match: $ETag" --header "content-type: multipart/form-data" --form file=@$FilePath --insecure -u $idrac_username_password
$execute_post_output = [string]$execute_post_output
$get_version = [regex]::Match($execute_post_output, 'Available.+?,').captures.groups[0].value
$get_version = $get_version.Replace(",","")
$get_version = $get_version.Replace('"',"")
$global:available_entry = "/redfish/v1/UpdateService/FirmwareInventory/"+$get_version


if ($execute_post_output.Contains("Package successfully downloaded"))
{
Write-Host "`n- INFO, package firmware successfully downloaded"
}
else
{
Write-Host "- FAIL, firmware package failed to download, detailed error results:"
$execute_post_output
exit
}

}


else
{
Write-Host "`n- INFO, downloading firmware image using iDRAC9, this may take a few minutes depending of the size of the image.`n"

$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory"
try
{
if ($global:get_powershell_version -gt 5)
    {
    $get_result = Invoke-WebRequest -SkipCertificateCheck -Uri $uri -Credential $credential -Method Get -UseBasicParsing -Headers @{"Accept"="application/json"} -SkipHeaderValidation
    $ETag=[string]$get_result.Headers.ETag
    }
    else
    {
    Ignore-SSLCertificates
    $get_result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    $ETag=$get_result.Headers.ETag
    }
}
catch
{
Write-Host
$RespErr
break
}


$complete_path=$image_directory_path + "\" + $image_filename
$headers = @{"If-Match" = $ETag; "Accept"="application/json"}


# Code to read the image file for download to the iDRAC

$CODEPAGE = "iso-8859-1"
$fileBin = [System.IO.File]::ReadAllBytes($complete_path)
$enc = [System.Text.Encoding]::GetEncoding($CODEPAGE)
$fileEnc = $enc.GetString($fileBin)
$boundary = [System.Guid]::NewGuid().ToString()

$LF = "`r`n"
$body = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$image_filename`"",
		"Content-Type: application/octet-stream$LF",
        $fileEnc,
        "--$boundary--$LF"
) -join $LF


# POST command to download the image payload to the iDRAC

try
{
    if ($global:get_powershell_version -gt 5)
    { 
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipCertificateCheck -Uri $uri -Credential $credential -Method Post -ContentType "multipart/form-data; boundary=`"$boundary`"" -Headers $headers -SkipHeaderValidation -SkipHttpErrorCheck -Body $body -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType "multipart/form-data; boundary=`"$boundary`"" -Headers $headers -Body $body -ErrorVariable RespErr
    
    }
}
catch
{
Write-Host
$RespErr
break
} 

if ($result1.StatusCode -eq 201)
{
    [String]::Format("- PASS, statuscode {0} returned successfully for POST command to download payload image to iDRAC",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned. Detail error message: {1}",$result1.StatusCode,$result1)
    return
}

$get_content=$result1.Content
$global:available_entry = $result1.Headers['Location']
}


}

# Function install image payload, query job status, reboot server

function install_image_payload_query_job_status_reboot_server

{

$uri = "https://$idrac_ip/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate"
$image_uri = [string]$global:available_entry
$JsonBody = @{'ImageURI'= $image_uri} | ConvertTo-Json -Compress

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result2 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Body $JsonBody -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result2 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -Body $JsonBody -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    } 
 

if ($result2.StatusCode -eq 202)
{
    $job_id_search=$result2.Headers['Location']
    $job_id=$job_id_search.Split("/")[-1]
    [String]::Format("- PASS, statuscode {0} returned successfully for POST command to create update job ID {1}",$result2.StatusCode, $job_id)
    Write-Host
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned. Detail error message: {1}",$result2.StatusCode,$result2)
    break
}

# Loop job status until marked completed or scheduled 

$get_time_old=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(30)
$force_count=0
Write-Host "- INFO, script will now loop polling the job status every 5 seconds until marked either scheduled or completed`n"
while ($true)
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/TaskService/Tasks/$job_id"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    }

$overall_job_output=$result.Content | ConvertFrom-Json

if ($overall_job_output.Messages.Message.Contains("Fail") -or $overall_job_output.Messages.Message.Contains("Failed") -or $overall_job_output.Messages.Message.Contains("fail") -or $overall_job_output.Messages.Message.Contains("failed") -or $overall_job_output.Messages.Message.Contains("Job for this device is already present") -or $overall_job_output.Messages.Message.Contains("unable") -or $overall_job_output.Messages.Message.Contains("Unable"))
{
Write-Host
[String]::Format("- FAIL, job id $job_id marked as failed, error message: {0}",$overall_job_output.Messages.Message)
break
}
elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 30 minutes has been reached before marking the job completed"
break
}

elseif ($overall_job_output.Messages.Message -eq "Task successfully scheduled.")
{
Write-Host "`n- PASS, job ID '$job_id' successfully marked as scheduled."
$job_completed = "no"
break
}
elseif ($overall_job_output.Messages.Message -eq "The specified job has completed successfully." -or $overall_job_output.Messages.Message -eq  "Job completed successfully." -or $overall_job_output.Messages.Message.Contains("complete"))
{
$get_current_time=Get-Date -DisplayHint Time
$final_time=$get_current_time-$get_time_old
$final_completion_time=$final_time | select Minutes,Seconds
Write-Host "`n- PASS, job ID '$job_id' successfully marked as completed"
Write-Host "`nFirmware update job execution time:"
$final_completion_time
return
}
else
{
Write-Host "- Job ID '$job_id' not marked scheduled or completed, checking job status again"
Start-Sleep 5
}

}

# Reboot server

if ($reboot_server.ToLower() -eq "n" -and $job_completed -eq "no")
{
Write-Host "- INFO, user selected to not automatically reboot the server. Update job is scheduled and will be applied on next server manual reboot"
break
}

elseif ($reboot_server.ToLower() -eq "y" -and $job_completed -eq "yes")
{
Write-Host "- INFO, no server reboot is needed since job ID is already marked completed, immediate update was performed"
break
}

elseif ($reboot_server.ToLower() -eq "y")
{
Write-Host "- INFO, user selected to reboot the server now to apply the firmware update"
}

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/"
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    }

if ($result.StatusCode -eq 200)
{
    Write-Host
    [String]::Format("- PASS, statuscode {0} returned successfully to get current power state",$result.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result.StatusCode)
    break
}

$result_output = $result.Content | ConvertFrom-Json
$power_state = $result_output.PowerState

if ($power_state -eq "On")
{
Write-Host "- INFO, Server current power state is ON, performing graceful shutdown"



$JsonBody = @{ "ResetType" = "GracefulShutdown"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Body $JsonBody -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -Body $JsonBody -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    } 

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to attempt graceful server shutdown",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}

$count = 1
while($true)
{
$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/"
try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    }

$result_output = $result.Content | ConvertFrom-Json
$power_state = $result_output.PowerState

if ($power_state -eq "Off")
{
Write-Host "- PASS, validated server in OFF state"
break
}
elseif ($count -eq 5)
{
Write-Host "- INFO, server did not accept graceful shutdown request, performing force off"

$JsonBody = @{ "ResetType" = "ForceOff"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Body $JsonBody -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -Body $JsonBody -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    } 

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned to force power OFF the server",$result1.StatusCode)
    Start-Sleep 15
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}

}
else
{
Write-Host "- INFO, server still in ON state waiting for graceful shutdown to complete, will check server status again in 1 minute"
$count++
Start-Sleep 60
continue
}
}

$JsonBody = @{ "ResetType" = "On"
    } | ConvertTo-Json -Compress

$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Body $JsonBody -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -Body $JsonBody -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    } 

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
    $power_state = "On"
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}
}


if ($power_state -eq "Off")
{
$JsonBody = @{ "ResetType" = "On"
    } | ConvertTo-Json -Compress


$uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"

# POST command to power ON the server

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    
    $result1 = Invoke-WebRequest -UseBasicParsing -SkipHeaderValidation -SkipCertificateCheck -Uri $uri -Credential $credential -Body $JsonBody -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -ErrorVariable RespErr
    }
    else
    {
    Ignore-SSLCertificates
    $result1 = Invoke-WebRequest -UseBasicParsing -Uri $uri -Credential $credential -Method Post -ContentType 'application/json' -Headers @{"Accept"="application/json"} -Body $JsonBody -ErrorVariable RespErr
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    } 

if ($result1.StatusCode -eq 204)
{
    [String]::Format("- PASS, statuscode {0} returned successfully to power ON the server",$result1.StatusCode)
}
else
{
    [String]::Format("- FAIL, statuscode {0} returned",$result1.StatusCode)
    break
}

}

# Loop job status until marked completed 

$get_time_old=Get-Date -DisplayHint Time
$start_time = Get-Date
$end_time = $start_time.AddMinutes(50)
$force_count=0
Write-Host "- INFO, script will now loop polling the job status every 30 seconds until marked completed`n"
while ($true)
{
$loop_time = Get-Date
$uri ="https://$idrac_ip/redfish/v1/TaskService/Tasks/$job_id"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host
    $RespErr
    break
    }

$overall_job_output=$result.Content | ConvertFrom-Json
$current_job_message = "$overall_job_output.Messages.Message"

if ($overall_job_output.Messages.Message.Contains("Fail") -or $overall_job_output.Messages.Message.Contains("Failed") -or $overall_job_output.Messages.Message.Contains("fail") -or $overall_job_output.Messages.Message.Contains("failed"))
{
Write-Host
[String]::Format("- FAIL, job id $job_id marked as failed, error message: {0}",$overall_job_output.Messages.Message)
break
}
elseif ($loop_time -gt $end_time)
{
Write-Host "- FAIL, timeout of 50 minutes has been reached before marking the job completed"
break
}
elseif ($overall_job_output.Messages.Message -eq "The specified job has completed successfully." -or $overall_job_output.Messages.Message -eq  "Job completed successfully." -or $overall_job_output.Messages.Message.Contains("complete"))
{
$get_current_time=Get-Date -DisplayHint Time
$final_time=$get_current_time-$get_time_old
$final_completion_time=$final_time | select Minutes,Seconds
Write-Host "`n- PASS, job ID '$job_id' successfully marked as completed"
Write-Host "`nFirmware update job execution time:"
$final_completion_time
break
}
else
{
Write-Host "- Job ID '$job_id' not marked completed, checking job status again"
Start-Sleep 30
}

}

}

# Run cmdlet

get_powershell_version
setup_idrac_creds

# Code to check for supported iDRAC version installed

$query_parameter = "?`$expand=*(`$levels=1)" 
$uri = "https://$idrac_ip/redfish/v1/UpdateService/FirmwareInventory$query_parameter"

try
    {
    if ($global:get_powershell_version -gt 5)
    {
    $result = Invoke-WebRequest -SkipCertificateCheck -SkipHeaderValidation -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    else
    {
    Ignore-SSLCertificates
    $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
    }
    }
    catch
    {
    Write-Host "`n- INFO, iDRAC version detected does not support this feature using Redfish API or incorrect iDRAC user credentials passed in.`n"
    $RespErr
    return
    }



if ($view_fw_inventory_only.ToLower() -eq "y")
{
get_firmware_versions
}

elseif ($image_directory_path -and $image_filename)
{
download_image_payload
install_image_payload_query_job_status_reboot_server
}

else
{
Write-Host "- FAIL, either incorrect parameter(s) used or missing required parameters(s)"
}



}








