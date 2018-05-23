# Asking for the user for their Asset

DEP currently has no mechanism to name a Mac during the onboarding process

## How to use this script

During enrolment a bind script runs to check the computer name and if it doesn't meet the correct convention gets renamed to it's serial number and then bound to AD.

This script is designed to then be ran at first login (or via Self Service) to ask the user to enter the asset number that is attached to the Mac. There script take the input gathered via AppleScript does some basic checks and then if passed the the following steps are taken

- Unbind From AD (This removes the computer record of the serial number from AD)
- rename the computer based on the user input
- bind to AD
- Reboot

