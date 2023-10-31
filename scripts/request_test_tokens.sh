active_address=$(sui client active-address)

check() {
    gas_response=$(sui client gas --json)

    if [ ${#gas_response} -gt 2 ]; then
        echo "This address already has test tokens."
        exit 0
    else
        res=request
        echo "Got test tokens from the faucet."
        exit 0
    fi
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

echo "Requesting test tokens for: '$active_address'"

check
