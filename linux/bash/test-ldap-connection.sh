#!/bin/bash

# LDAP Connection Test Tool - Linux Version

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Check and install ldap-utils
check_and_install_ldap_tools() {
    if command -v ldapsearch &> /dev/null; then
        echo -e "${GREEN}✓ LDAP tools already installed${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠ LDAP tools not detected, installing...${NC}"
    
    # Detect operating system
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif command -v uname &> /dev/null; then
        OS=$(uname -s)
    else
        echo -e "${RED}✗ Unable to detect operating system${NC}"
        exit 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            echo -e "${CYAN}Detected Ubuntu/Debian system${NC}"
            sudo apt-get update
            sudo apt-get install -y ldap-utils
            ;;
        centos|rhel|fedora)
            echo -e "${CYAN}Detected CentOS/RHEL/Fedora system${NC}"
            sudo yum install -y openldap-clients
            ;;
        rocky|almalinux)
            echo -e "${CYAN}Detected Rocky/AlmaLinux system${NC}"
            sudo dnf install -y openldap-clients
            ;;
        arch|manjaro)
            echo -e "${CYAN}Detected Arch/Manjaro system${NC}"
            sudo pacman -S --noconfirm openldap
            ;;
        Darwin)
            echo -e "${CYAN}Detected macOS system${NC}"
            if command -v brew &> /dev/null; then
                brew install openldap
            else
                echo -e "${RED}✗ Please install Homebrew first: https://brew.sh${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}✗ Unsupported operating system: $OS${NC}"
            echo -e "${YELLOW}Please manually install ldap-utils or openldap-clients${NC}"
            exit 1
            ;;
    esac
    
    # Verify installation
    if command -v ldapsearch &> /dev/null; then
        echo -e "${GREEN}✓ LDAP tools installed successfully${NC}"
    else
        echo -e "${RED}✗ LDAP tools installation failed${NC}"
        exit 1
    fi
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}LDAP Connection Test Tool${NC}"
echo -e "${CYAN}========================================${NC}"

# Check and install LDAP tools
check_and_install_ldap_tools

echo ""

# User input parameters
read -p "Enter LDAP Server IP: " server
read -p "Enter Port (default 389, GC use 3268) [389]: " port
port=${port:-389}

read -p "Enter Username (e.g., dev\\hank_lin or user@domain.com): " username
read -sp "Enter Password: " password
echo ""

read -p "Enter Search Base (e.g., DC=dev,DC=gss): " searchBase

ldapUrl="ldap://${server}:${port}"

echo ""
echo -e "${YELLOW}Starting connection test...${NC}"
echo -e "${GRAY}Server: $server${NC}"
echo -e "${GRAY}Port: $port${NC}"
echo -e "${GRAY}Username: $username${NC}"
echo -e "${GRAY}Base DN: $searchBase${NC}"

connectionSuccess=false
querySuccess=false

# Test 1: Basic connection verification
echo ""
echo -e "${YELLOW}[Test 1] Verifying connection...${NC}"

# Use timeout to avoid long waits
timeout 10 ldapsearch -x -H "$ldapUrl" -D "$username" -w "$password" -b "" -s base "(objectClass=*)" namingContexts &> /dev/null

exitCode=$?

if [ $exitCode -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ Connection successful!✓✓✓${NC}"
    echo -e "${YELLOW}Path: $ldapUrl${NC}"
    connectionSuccess=true
elif [ $exitCode -eq 124 ]; then
    echo -e "${RED}✗ Connection timeout${NC}"
    echo -e "${YELLOW}Please check network connection and firewall settings${NC}"
    exit 1
elif [ $exitCode -eq 49 ]; then
    echo -e "${RED}✗ Authentication failed${NC}"
    echo -e "${YELLOW}Please check if username and password are correct${NC}"
    exit 1
else
    echo -e "${RED}✗ Connection failed (error code: $exitCode)${NC}"
    echo -e "${YELLOW}Possible reasons:${NC}"
    echo -e "${GRAY}  - Incorrect server IP or port${NC}"
    echo -e "${GRAY}  - Wrong username or password${NC}"
    echo -e "${GRAY}  - Network unreachable or firewall blocking${NC}"
    exit 1
fi

if [ "$connectionSuccess" = true ]; then
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}✓ Connection verification successful${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${YELLOW}Using account: $username${NC}"
    
    # Test 2: Query users
    echo ""
    echo -e "${YELLOW}[Additional Test] Querying users...${NC}"
    
    # Execute query and capture results
    queryResult=$(timeout 10 ldapsearch -x -H "$ldapUrl" -D "$username" -w "$password" \
        -b "$searchBase" -s sub \
        "(&(objectClass=user)(objectCategory=person))" \
        cn sAMAccountName dn -LLL 2>&1)
    
    queryExitCode=$?
    
    if [ $queryExitCode -eq 0 ]; then
        # Count the number of users found
        userCount=$(echo "$queryResult" | grep -c "^dn:")
        
        if [ $userCount -gt 0 ]; then
            echo -e "${GREEN}✓ Successfully queried $userCount users${NC}"
            querySuccess=true
            
            # Parse and display first 3 users
            echo "$queryResult" | awk '
                BEGIN { count=0 }
                /^dn:/ { 
                    if (count >= 3) exit
                    dn=$0
                    getline
                    while ($0 != "" && count < 3) {
                        if ($1 == "cn:") cn=$2
                        if ($1 == "sAMAccountName:") sam=$2
                        getline
                    }
                    if (cn != "" || sam != "") {
                        printf "  - %s (%s)\n", (cn != "" ? cn : "N/A"), (sam != "" ? sam : "N/A")
                        count++
                    }
                    cn=""; sam=""
                }
            '
        else
            echo -e "${YELLOW}⚠ No users found${NC}"
            echo -e "${GRAY}  Possible reasons:${NC}"
            echo -e "${GRAY}  1. Incorrect Search Base configuration${NC}"
            echo -e "${GRAY}  2. No users under this path${NC}"
            echo -e "${GRAY}  3. Account lacks query permissions${NC}"
        fi
    elif [ $queryExitCode -eq 124 ]; then
        echo -e "${RED}✗ Query timeout${NC}"
        echo -e "${YELLOW}Search Base may be too large or network delay${NC}"
    elif [ $queryExitCode -eq 32 ]; then
        echo -e "${RED}✗ Query failed - Search Base does not exist${NC}"
        echo -e "${GRAY}Possible reasons:${NC}"
        echo -e "${GRAY}  1. Incorrect Search Base (DC) configuration: $searchBase${NC}"
        echo -e "${GRAY}  2. Path does not exist${NC}"
        echo ""
        echo -e "${YELLOW}Suggestions:${NC}"
        echo -e "${GRAY}  - Check if DN format is correct${NC}"
        echo -e "${GRAY}  - Try using a higher level DN (e.g., DC=gss)${NC}"
    else
        echo -e "${RED}✗ Query failed (error code: $queryExitCode)${NC}"
        # Display partial error message
        errorMsg=$(echo "$queryResult" | head -n 3)
        if [ -n "$errorMsg" ]; then
            echo -e "${YELLOW}Error message: $errorMsg${NC}"
        fi
        echo ""
        echo -e "${GRAY}Possible reasons:${NC}"
        echo -e "${GRAY}  1. Incorrect Search Base configuration${NC}"
        echo -e "${GRAY}  2. Account lacks query permissions${NC}"
        echo -e "${GRAY}  3. LDAP server configuration issue${NC}"
    fi
fi

# Display recommended Java configuration
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Recommended Java LDAP Configuration:${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${YELLOW}ldapUrl = \"$ldapUrl\"${NC}"

if [ "$querySuccess" = true ]; then
    echo -e "${YELLOW}baseDn = \"$searchBase\"${NC}"
else
    echo -e "${RED}baseDn = \"(Query failed, please check Search Base configuration)\"${NC}"
fi

echo -e "${YELLOW}bindDn = \"$username\"${NC}"
echo -e "${YELLOW}password = \"********\"${NC}"

echo ""
echo -e "${CYAN}Test completed!${NC}"