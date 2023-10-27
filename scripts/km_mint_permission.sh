# Read the values from objects.json using jq
rsc_package_id=$(jq -r '.package_id' contracts/tokens/objects.json)
rsc_admin_cap=$(jq -r '.rusd_stable_coin.admin_cap' contracts/tokens/objects.json)
rsc_storage=$(jq -r '.rusd_stable_coin.storage' contracts/tokens/objects.json)
km_publisher_id=$(jq -r '.kasa_manager.publisher_id' contracts/stable_coin_factory/objects.json)

response=$(sui client call --json --package $rsc_package_id \
    --module rusd_stable_coin \
    --function add_manager \
    --args $rsc_admin_cap $rsc_storage $km_publisher_id \
    --gas-budget 20000000)
