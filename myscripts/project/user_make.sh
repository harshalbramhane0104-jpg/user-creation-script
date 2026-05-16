#!/bin/bash

# Script should be executed with sudo/root access
if [[ "${UID}" -ne 0 ]]
then
        echo "Please run with sudo or root"
        exit 1
fi

# Ask for username
read -p "Enter username: " USER_NAME

# Validate username not empty
if [[ -z "${USER_NAME}" ]]
then
        echo "Username cannot be empty"
        exit 1
fi

# Ask for comment
read -p "Enter comment (Full Name or description): " COMMENT

# Create a password
PASSWORD=$(date +%s%N | sha256sum | head -c 12)

# Create the user
useradd -c "${COMMENT}" -m $USER_NAME

# Check if the user was successfully created
if [[ $? -ne 0 ]]
then
        echo "The account could not be created"
        exit 1
fi

# Set the password for the user
echo "$USER_NAME:$PASSWORD" | chpasswd

# Check if password was successfully set
if [[ $? -ne 0 ]]
then
        echo "Password could not be set"
        exit 1
fi

# Force password change on first login
passwd -e $USER_NAME

# Display the username, password and host where created
echo
echo "==============================="
echo "  Account Created Successfully"
echo "==============================="
echo "  Username : $USER_NAME"
echo "  Comment  : $COMMENT"
echo "  Password : $PASSWORD"
echo "  Hostname : $(hostname)"
echo "==============================="
echo "  User must change password on first login"
echo "==============================="
