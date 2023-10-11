# !/bin/bash

modules=("library" "tokens" "stable_coin_factory")

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

parse_response_object_changes() {
    echo "$1" | jq -r '.objectChanges[] | select(.objectType == "'$2'").objectId'
}

for module in "${modules[@]}"; do
    (
        cd "contracts/$module"

        echo "Publishing \"$module\" module..."
        echo ""

        # Set the address and published-at fields to 0x0
        update_toml_field $module "0x0"
        update_toml_field "published-at" "0x0"

        # Publish the contract and save response to a variable
        # TODO: Think about the budget in here
        response=$(sui client publish --json --gas-budget 2000000000)

        # Package ID of the module
        package_id=$(echo "$response" | jq -r '.objectChanges[] | select(.type == "published").packageId')
        
        # JSON file that will be saved
        json=""

        case $module in
            "library")
                json='{"package_id": "'$package_id'"}'
                ;;
            "tokens")
                storage=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::rusd_stable_coin::RUSDStableCoinStorage").objectId')
                admin_cap=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::rusd_stable_coin::RUSDStableCoinAdminCap").objectId')
                json='{
                    "package_id": "'$package_id'",
                    "rusd_stable_coin": {
                        "storage": "'$storage'",
                        "coin_type": "'$package_id'::rusd_stable_coin::RUSD_STABLE_COIN",
                        "admin_cap": "'$admin_cap'"
                    }
                }'
                ;;
            "stable_coin_factory")
                km_storage=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::kasa_storage::KasaManagerStorage").objectId')
                km_publisher=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::kasa_manager::KasaManagerPublisher").objectId')
                sk_storage=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::sorted_kasas::SortedKasasStorage").objectId')
                sp_publisher=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::stability_pool::StabilityPoolPublisher").objectId')
                sp_storage=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::stability_pool::StabilityPoolStorage").objectId')
                collateral_gains=$(echo "$response" | jq -r '.objectChanges[] | select(.objectType == "'$package_id'::liquidation_assets_distributor::CollateralGains").objectId')
                json='{
                    "package_id": "'$package_id'",
                    "kasa_storage": {
                        "km_storage": "'$km_storage'"
                    },
                    "kasa_manager": {
                        "publisher": "'$km_publisher'"
                    },
                    "sorted_kasas": {
                        "storage": "'$sk_storage'"
                    },
                    "stability_pool": {
                        "publisher": "'$sp_publisher'",
                        "storage": "'$sp_storage'"
                    },
                    "liquidation_assets_distributor": {
                        "collateral_gains": "'$collateral_gains'"
                    }
                }'
                echo "$json"
                ;;
        esac

        # Save the JSON file
        echo "$json" | jq '.' > objects.json

        # Update the Move.toml file with the new module ID
        update_toml_field $module $package_id
        update_toml_field "published-at" $package_id
        
        echo ""
    )
done

