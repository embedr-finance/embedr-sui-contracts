# !/bin/bash

BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

echo -e "${BOLD}${BLUE}Adding Managers to rUSD Stable Coin${NC}\n"

rsc_package_id=$(jq -r '.package_id' contracts/tokens/objects.json)
rsc_admin_cap=$(jq -r '.rusd_stable_coin.admin_cap' contracts/tokens/objects.json)
rsc_storage=$(jq -r '.rusd_stable_coin.storage' contracts/tokens/objects.json)

km_publisher_id=$(jq -r '.kasa_manager.publisher_id' contracts/stable_coin_factory/objects.json)

sp_publisher_id=$(jq -r '.stability_pool.publisher_id' contracts/stable_coin_factory/objects.json)

rfp_publisher_id=$(jq -r '.revenue_farming_pool.publisher_id' contracts/participation_bank_factory/objects.json)

echo "${RED}Adding Kasa Manager${NC}"

response=$(sui client call --json --package $rsc_package_id \
    --module rusd_stable_coin \
    --function add_manager \
    --args $rsc_admin_cap $rsc_storage $km_publisher_id \
    --gas-budget 20000000)

echo -e "${GREEN}Kasa Manager addded${NC}\n"

echo "${RED}Adding Stability Pool${NC}"

response=$(sui client call --json --package $rsc_package_id \
    --module rusd_stable_coin \
    --function add_manager \
    --args $rsc_admin_cap $rsc_storage $sp_publisher_id \
    --gas-budget 20000000)

echo -e "${GREEN}Stability Pool addded${NC}\n"

echo "${RED}Adding Revenue Farming Pool${NC}"

response=$(sui client call --json --package $rsc_package_id \
    --module rusd_stable_coin \
    --function add_manager \
    --args $rsc_admin_cap $rsc_storage $rfp_publisher_id \
    --gas-budget 20000000)

echo -e "${GREEN}Revenue Farming Pool addded${NC}\n"

exit 0
