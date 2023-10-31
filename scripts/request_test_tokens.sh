# !/bin/bash

BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

active_address=$(sui client active-address)

check() {
    gas_response=$(sui client gas --json)

    if [ ${#gas_response} -gt 2 ]; then
        echo "${RED}This address already has test tokens.${NC}"
    else
        res=request
        echo "${GREEN}Got test tokens from the faucet.${NC}"
    fi

    echo ""
    
    exit 0
}

request() {
    curl --location --request POST 'https://faucet.devnet.sui.io/gas' \
    --header 'Content-Type: application/json' \
    --data-raw '{
        "FixedAmountRequest": {
            "recipient": "'$active_address'"
        }
    }'
}

echo -e "${BOLD}${BLUE}Requesting Test Tokens${NC}\n"

echo -e "Current address: '$active_address'\n"

check
