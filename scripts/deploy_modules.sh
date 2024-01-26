# !/bin/bash

BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
BOLD=$(tput bold)
NC=$(tput sgr0)

modules=("library" "tokens" "oracles" "stable_coin_factory" "participation_bank_factory")

update_toml_field() {
    file="Move.toml"
    content=$(cat "$file")
    # Find the line containing "module_name ="
    line=$(echo "$content" | grep -n "$1 =" | cut -d ":" -f 1)
    # Extract the current value of "module_name"
    current_value=$(echo "$content" | sed -n "${line}p" | awk -F'"' '{print $2}')
    # Generate a new value for "module_name"
    new_value=$2
    # Replace the current value with the new value
    updated_content=$(echo "$content" | sed "${line}s/$current_value/$new_value/")
    # Write the updated content back to the Move.toml file
    echo "$updated_content" > "$file"
}

get_object_id_from_object_type() {
    echo "$1" | jq -r '.objectChanges[] | select(.objectType == "'$2'").objectId'
}

get_publisher_id_from_object() {
    sui client object --json $1 | jq -r '.content.fields.publisher.fields.id.id'
}

get_table_id_from_object() {
    sui client object --json $1 | jq -r '.content.fields.'$2'.fields.id.id'
}

echo -e "${BOLD}${BLUE}Publishing Embedr Protocol Contracts${NC}\n"

for module in "${modules[@]}"; do
    (
        cd "contracts/$module"

        echo -e "${RED}Publishing \"$module\" module...${NC}\n"

        # Set the address and published-at fields to 0x0
        update_toml_field $module "0x0"
        update_toml_field "published-at" "0x0"

        # Publish the contract and save response to a variable
        # TODO: Think about the budget in here
        response=$(sui client publish --json --gas-budget 500000000)

        # Package ID of the module
        package_id=$(echo "$response" | jq -r '.objectChanges[] | select(.type == "published").packageId')
        
        # JSON file that will be saved
        json=""

        case $module in
            "library")
                json='{"package_id": "'$package_id'"}'
            ;;
            "tokens")
                # rUSD Stable Coin
                rsc_coin_type="$package_id::rusd_stable_coin::RUSD_STABLE_COIN"
                rsc_storage=$(get_object_id_from_object_type "$response" "$package_id"::rusd_stable_coin::RUSDStableCoinStorage)
                rsc_admin_cap=$(get_object_id_from_object_type "$response" "$package_id"::rusd_stable_coin::RUSDStableCoinAdminCap)
                rsc_balance_table_id=$(get_table_id_from_object "$rsc_storage" "balances")

                # EMBD Incentive Token
                eit_coin_type="$package_id::embd_incentive_token::EMBD_INCENTIVE_TOKEN"
                eit_storage=$(get_object_id_from_object_type "$response" "$package_id"::embd_incentive_token::EMBDIncentiveTokenStorage)
                eit_admin_cap=$(get_object_id_from_object_type "$response" "$package_id"::embd_incentive_token::EMBDIncentiveTokenAdminCap)
                eit_balance_table_id=$(get_table_id_from_object "$eit_storage" "balances")

                # EMBD Staking
                es_publisher_object=$(get_object_id_from_object_type "$response" "$package_id"::embd_staking::EMBDStakingPublisher)
                es_publisher_id=$(get_publisher_id_from_object "$es_publisher_object")
                es_storage=$(get_object_id_from_object_type "$response" "$package_id"::embd_staking::EMBDStakingStorage)
                es_stake_table_id=$(get_table_id_from_object "$es_storage" "stake_table")

                json='{
                    "package_id": "'$package_id'",
                    "rusd_stable_coin": {
                        "storage": "'$rsc_storage'",
                        "coin_type": "'$rsc_coin_type'",
                        "admin_cap": "'$rsc_admin_cap'",
                        "balance_table_id": "'$rsc_balance_table_id'"
                    },
                    "embd_incentive_token": {
                        "storage": "'$eit_storage'",
                        "coin_type": "'$eit_coin_type'",
                        "admin_cap": "'$eit_admin_cap'",
                        "balance_table_id": "'$eit_balance_table_id'"
                    },
                    "embd_staking": {
                        "publisher_object": "'$es_publisher_object'",
                        "publisher_id": "'$es_publisher_id'",
                        "storage": "'$es_storage'",
                        "stake_table_id": "'$es_stake_table_id'"
                    }
                }'
            ;;
            "stable_coin_factory")
                # Kasa Storage
                km_storage=$(get_object_id_from_object_type "$response" "$package_id"::kasa_storage::KasaManagerStorage)

                # Kasa Manager
                km_publisher_object=$(get_object_id_from_object_type "$response" "$package_id"::kasa_manager::KasaManagerPublisher)
                km_publisher_id=$(get_publisher_id_from_object "$km_publisher_object")
                km_kasa_table_id=$(get_table_id_from_object "$km_storage" "kasa_table")

                # Sorted Kasas
                sk_storage=$(get_object_id_from_object_type "$response" "$package_id"::sorted_kasas::SortedKasasStorage)

                # Stability Pool
                sp_publisher_object=$(get_object_id_from_object_type "$response" "$package_id"::stability_pool::StabilityPoolPublisher)
                sp_publisher_id=$(get_publisher_id_from_object "$sp_publisher_object")
                sp_storage=$(get_object_id_from_object_type "$response" "$package_id"::stability_pool::StabilityPoolStorage)
                sp_stake_table_id=$(get_table_id_from_object "$sp_storage" "stake_table")
                
                # Liquidation Assets Distributor
                collateral_gains=$(get_object_id_from_object_type "$response" "$package_id"::liquidation_assets_distributor::CollateralGains)
                
                json='{
                    "package_id": "'$package_id'",
                    "kasa_storage": {
                        "km_storage": "'$km_storage'"
                    },
                    "kasa_manager": {
                        "publisher_object": "'$km_publisher_object'",
                        "publisher_id": "'$km_publisher_id'",
                        "kasa_table_id": "'$km_kasa_table_id'"
                    },
                    "sorted_kasas": {
                        "storage": "'$sk_storage'"
                    },
                    "stability_pool": {
                        "publisher_object": "'$sp_publisher_object'",
                        "publisher_id": "'$sp_publisher_id'",
                        "storage": "'$sp_storage'",
                        "stake_table_id": "'$sp_stake_table_id'"
                    },
                    "liquidation_assets_distributor": {
                        "collateral_gains": "'$collateral_gains'"
                    }
                }'
            ;;
            "participation_bank_factory")
                # Revenue Farming Pool
                rfp_publisher_object=$(get_object_id_from_object_type "$response" "$package_id"::revenue_farming_pool::RevenueFarmingPoolPublisher)
                rfp_publisher_id=$(get_publisher_id_from_object "$rfp_publisher_object")
                rfp_storage=$(get_object_id_from_object_type "$response" "$package_id"::revenue_farming_pool::RevenueFarmingPoolStorage)
                rfp_admin_cap=$(get_object_id_from_object_type "$response" "$package_id"::revenue_farming_pool::RevenueFarmingPoolAdminCap)

                json='{
                    "package_id": "'$package_id'",
                    "revenue_farming_pool": {
                        "publisher_object": "'$rfp_publisher_object'",
                        "publisher_id": "'$rfp_publisher_id'",
                        "storage": "'$rfp_storage'",
                        "admin_cap": "'$rfp_admin_cap'"
                    }
                }'
            ;;
            "oracles")
                json='{"package_id": "'$package_id'"}'
            ;;
        esac

        # Save the JSON file
        echo "$json" | jq '.' > objects.json

        # Update the Move.toml file with the new module ID
        update_toml_field $module $package_id
        update_toml_field "published-at" $package_id
        
        echo -e "\n${GREEN}Published \"$module\" module with package ID: $package_id${NC}\n"
    )
done

exit 0
