#!/bin/bash
 
# File paths
SERVER_LIST="/data/automation/os_config/redhat_os_config/servers.txt"
PASSWORD_FILE="/data/automation/os_config/redhat_os_config/password.txt.enc"
LOG_FILE="ssh_setup.log"
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_KEY_PUB="$HOME/.ssh/id_rsa.pub"
 
# Create log file if it doesn't exist
touch "$LOG_FILE"
 
# Check for required files
if [ ! -f "$SERVER_LIST" ]; then
    echo "Error: Server list file '$SERVER_LIST' not found." | tee -a "$LOG_FILE"
    exit 1
fi
 
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "Error: Password file '$PASSWORD_FILE' not found." | tee -a "$LOG_FILE"
    exit 1
fi
 
# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is not installed. Please install it first." | tee -a "$LOG_FILE"
    exit 1
fi
 
read -s -p "Enter password file decryption passphrase: " PASSPHRASE
echo
 
# =======================
# Decrypt passwords into array (no temp file)
# =======================
mapfile -t PASSWORDS < <(
    openssl enc -aes-256-cbc -d -salt \
    -in "$PASSWORD_FILE" \
    -pass pass:"$PASSPHRASE" 2>> "$LOG_FILE"
)
 
if [ ${#PASSWORDS[@]} -eq 0 ]; then
    echo "Error: Failed to decrypt password file." | tee -a "$LOG_FILE"
    exit 1
fi
 
 
# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_KEY" ] || [ ! -f "$SSH_KEY_PUB" ]; then
    echo "Generating SSH key pair..." | tee -a "$LOG_FILE"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate SSH key pair." | tee -a "$LOG_FILE"
        exit 1
    fi
fi
 
# Read each server from the list
while IFS= read -r SERVER; do
    if [ -z "$SERVER" ]; then
        continue
    fi
 
    echo "Processing server: $SERVER" | tee -a "$LOG_FILE"
 
    # Check SSH connectivity
    ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$SERVER" 'exit' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "SSH already set up for $SERVER" | tee -a "$LOG_FILE"
        continue
    fi
 
    # Try each password
    SUCCESS=0
    for PASSWORD in "${PASSWORDS[@]}"; do
        echo "Trying password for $SERVER..." | tee -a "$LOG_FILE"
 
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password root@"$SERVER" 'exit' 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Password accepted for $SERVER. Copying SSH key..." | tee -a "$LOG_FILE"
 
            PUB_KEY=$(cat "$SSH_KEY_PUB")
            sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password root@"$SERVER" << EOF
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys << KEY
$PUB_KEY
KEY
chmod 600 ~/.ssh/authorized_keys
EOF
 
            if [ $? -eq 0 ]; then
                echo "SSH setup successful for $SERVER" | tee -a "$LOG_FILE"
                SUCCESS=1
                break
            else
                echo "SSH key copy failed for $SERVER" | tee -a "$LOG_FILE"
            fi
        fi
    done
 
    if [ $SUCCESS -eq 0 ]; then
        echo "SSH setup failed for $SERVER after trying all passwords." | tee -a "$LOG_FILE"
    fi
done < "$SERVER_LIST"
