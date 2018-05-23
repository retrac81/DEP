#!/bin/sh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# VARIABLES ---
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

#Get the logged in user
LoggedInUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`
echo "Current user is $LoggedInUser"
#Go get the Bauer icon from Bauer Homepage website
curl -s --url https://www.bauermedia.com/fileadmin/site/img/logo_header.png > /var/tmp/bauer_logo.png
#Variables for the reBind
theUser="$4"									# Username for AD bind account pulled from policy in JSS
thePass="$5"								# password for the AD account pulled from policy in JSS
theDomain="$6"				# AD forest for bind pulled from policy in JSS
theOU="$6" 				#OU to ad computer accounts too pulled from policy in JSS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Functions to be used by the script
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkHostName ()
{
  #Get the hostname
  hostName=$(scutil --get ComputerName)
  #Check if the hostname contains wks and report result
  if [[ $hostName == wks* ]]; then
    echo "$hostName Correct hostname already nothing to do"
    exit 0
  else
    echo "This Mac hostname - $hostName is incorrectly formatted, prompt to update."
  fi
}

function getComputerName ()
{
ComputerName=$(su - $LoggedInUser -c /usr/bin/osascript <<EndGetComputerName
with timeout of (43200) seconds
tell application "System Events"
    activate
    set the_results to (display dialog ("Your computer name is incorrect, please provide the correct asset number from the Bauer asset sticker on your Mac

    Asset numbers consist of 5 numbers only!

    This Mac will RESTART to complete renaming process!") with title ("Enter Asset Number") buttons {"Cancel", "Continue"} default button "Continue" default answer "")
    set BUTTON_Returned to button returned of the_results
    set wks to text returned of the_results
end tell
end timeout
EndGetComputerName
)

echo "Asset Number Provided : $ComputerName"
wksComputerName="wks$ComputerName"
echo "New Computer name will be $wksComputerName"
}

function updateComputerName ()
{
echo "Updating mac computer name..."
/usr/sbin/scutil --set ComputerName "${wksComputerName}"
/usr/sbin/scutil --set LocalHostName "${wksComputerName}"
/usr/sbin/scutil --set HostName "${wksComputerName}"

dscacheutil -flushcache

#Get the hostname
hostName=$(scutil --get ComputerName)
echo "scutil now reporting hostname as : $hostName"

}

function rebindtoAD ()
{
#UnBind the Mac - remove the ad record
echo "Unbind from Bauer UK Domain"
dsconfigad -remove -u "$theUser" -p "$thePass"
echo "Attempt binding to Bauer UK"
#Bind the Mac using the new hostname and OU
/usr/local/jamf/bin/jamf bind -type ad -domain "$theDomain" -computerID "$hostName" -username "$theUser" -password "$thePass" -ou "$theOU" -cache -defaultShell /bin/bash -localHomes
#Add the computer name to the asset tag field in the JSS
echo "Update Asset Tag in JSS"
jamf recon -assetTag "$hostName"
#Set the computer name in JSS to match the new hostname
echo "Update hostname in JSS"
jamf -setComputerName -name "$hostName"
#jamf recon
}

function jamfHelperBindingInProgress ()
{

/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -icon /var/tmp/bauer_logo.png -title "Message from Bauer IT" -heading "Joining $hostName to the Bauer UK Network ⌛️" -description "Please wait for this Mac to finish joing the Bauer UK network.

Once this process has completed the Mac will restart" &
}

function jamfHelperHostnameUpdatedFail ()
{

/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -icon /Library/Application\ Support/JAMF/bin/Management\ Action.app/Contents/Resources/Self\ Service.icns -title "Message from Bauer IT" -heading "Oops Something went wrong" -description "Please call the IT Service Desk for assistance" -button1 "Ok" -defaultButton 1
}

function jamfHelperBadComputerName ()
{

/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -icon /Library/Application\ Support/JAMF/bin/Management\ Action.app/Contents/Resources/Self\ Service.icns -title "Message from Bauer IT" -heading "Invalid Asset Tag" -description "$ComputerName is not valid.

Asset tags consist 5 numbers" -button1 "Ok" -defaultButton 1
}

########################################################################
#####################     Start the script      ########################
########################################################################
#First up check if anyone is home, if not then can't ask for asset just yet
if [ "$LoggedInUser" == "" ]; then
        echo "No one home, try again later"
        exit 0
fi
#Call function to check current hostname
checkHostName

#Check that the asset tag only has numbers
while ! [[ $ComputerName =~ ^[0-9]+$ && $ComputerNamesize == 5 ]]
do
  #Call function to ask for the asset tag
  getComputerName
  #Count how many integers in string entered
  ComputerNamesize=${#ComputerName}
  #DEBUGecho "User entered this many numbers $ComputerNamesize"
  #After user input check if it formatted correctly and if not show jamfHelper
  if ! [[ $ComputerName =~ ^[0-9]+$ && $ComputerNamesize == 5 ]]; then
    jamfHelperBadComputerName
  fi
done

#Update hostname to JSS
updateComputerName

if [[ "$hostName" == "$wksComputerName" ]]; then
  echo "hostname: $hostName on computer matches asset tag entered: $ComputerName"
  echo "Show message that AD binding is in progress"
  jamfHelperBindingInProgress
  #ReBind to AD with new hostname
  rebindtoAD
  #Kill bitbar to read to hostname
  echo "Reload bitbar to show new hostname"
  killall BitBarDistro
  echo "Wait 5 seconds for things to calm down"
  sleep 5
  echo "REBOOT TO FINALISE"
  shutdown -r now
  else
    echo "hostname: $hostName on computer does NOT match asset tag entered: $ComputerName"
    jamfHelperHostnameUpdatedFail
    exit 1
fi
