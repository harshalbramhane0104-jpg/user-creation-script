#!/bin/bash
if [[ "${UID}" -ne 0 ]]
then
        echo "Please run with sudo or root"
        exit 1
fi

read -p "Enter username: " USER_NAME

# Validate username not empty
if [[ -z "${USER_NAME}" ]]
then
        echo "Username cannot be empty"
        exit 1
fi
read -p "Enter comment (Full Name or description): " COMMENT

PASSWORD=$(date +%s%N | sha256sum | head -c 12)

useradd -c "${COMMENT}" -m $USER_NAME

if [[ $? -ne 0 ]]
then
        echo "The account could not be created"
        exit 1
fi

echo "$USER_NAME:$PASSWORD" | chpasswd

if [[ $? -ne 0 ]]
then
        echo "Password could not be set"
        exit 1
fi

passwd -e $USER_NAME

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
