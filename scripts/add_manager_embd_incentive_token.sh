# !/bin/bash

BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

echo -e "${BOLD}${BLUE}Adding Managers to EMBD Incentive Token${NC}\n"

eit_package_id=$(jq -r '.package_id' contracts/tokens/objects.json)
eit_admin_cap=$(jq -r '.embd_incentive_token.admin_cap' contracts/tokens/objects.json)
eit_storage=$(jq -r '.embd_incentive_token.storage' contracts/tokens/objects.json)

es_publisher_id=$(jq -r '.embd_staking.publisher_id' contracts/tokens/objects.json)

echo "${RED}Adding EMBD Staking${NC}"

response=$(sui client call --json --package $eit_package_id \
    --module embd_incentive_token \
    --function add_manager \
    --args $eit_admin_cap $eit_storage $es_publisher_id \
    --gas-budget 20000000)

echo -e "${GREEN}EMBD Staking addded${NC}\n"

exit 0
