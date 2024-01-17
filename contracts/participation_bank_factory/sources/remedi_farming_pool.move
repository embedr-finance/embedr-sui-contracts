module participation_bank_factory::remedi_farming_pool {
    use std::option::{Self, Option};

    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table_vec::{Self, TableVec};

    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN};

    const VERSION: u64 = 1;

    /// This struct will be used to store the balance of
    /// the users for each tranche
    /// 
    /// # Fields
    /// 
    /// * `balances` - Table of balances for each user
    /// * `total_balance` - Total balance of the tranche
    struct Tranche has store {
        users: TableVec<address>,
        balances: Table<address, Balance<RUSD_STABLE_COIN>>,
        total_balance: u64,
    }

    /// This struct will be used to store both tranches
    /// 
    /// # Fields
    /// 
    /// * `junior_tranche` - Junior tranche
    /// * `senior_tranche` - Senior tranche
    struct TrancheStorage has store {
        junior_tranche: Tranche,
        senior_tranche: Tranche,
    }

    struct LoanRequest has store {
        id: UID,
        amount: Balance<RUSD_STABLE_COIN>,
        duration: u64,
        interest_rate: Option<u64>,
        interest_rate_approval: bool,
        users: TableVec<address>,
        junior_balances: Table<address, u64>,
        senior_balances: Table<address, u64>,
    }

    struct ActiveLoan has store {
        id: UID,
        total_amount: u64,
        remaining_amount: Balance<RUSD_STABLE_COIN>,
        duration: u64,
        interest_rate: u64,
        users: TableVec<address>,
        junior_balances: Table<address, u64>,
        senior_balances: Table<address, u64>,
        repaid_installments: u64,
    }

    struct PoolStorage has key, store {
        id: UID,
        version: u64,
        tranches: TrancheStorage,
        loan_requests: TableVec<LoanRequest>, // these could be IDs
        active_loans: TableVec<ActiveLoan>,
        user_rewards: Table<address, Balance<RUSD_STABLE_COIN>>
    }
    
    fun init(ctx: &mut TxContext) {
        let tranches = TrancheStorage {
            junior_tranche: Tranche {
                users: table_vec::empty(ctx),
                balances: table::new(ctx),
                total_balance: 0,
            },
            senior_tranche: Tranche {
                users: table_vec::empty(ctx),
                balances: table::new(ctx),
                total_balance: 0,
            },
        };

        let pool_storage = PoolStorage {
            id: object::new(ctx),
            version: VERSION,
            tranches,
            loan_requests: table_vec::empty(ctx),
            active_loans: table_vec::empty(ctx),
            user_rewards: table::new(ctx),
        };

        transfer::share_object(pool_storage);
    }

    fun deposit() {
        // Save the balance of the user
        // Users need to select which tranche to deposit to

        // Users can deposit to both tranches
    }

    fun withdraw() {
        // Save the balance of the user
        // Users need to select which tranche to withdraw from

        // TODO: Is there a lock period before withdrawal?
    }

    fun request_liquidity() {
        // TODO: Will Remedi be able to request for multiple loans at a given time?
        // Let's start with only one request and we can see what's the best way to handle multiple requests

        // Calculate the amount of rUSD to take out from each tranche
        // Junior tranche can be fully used - calculate the amount that will be taken out from there
        
        // Junior balance / 0.7 = total amount that can be given as loan
        // 0.3 * total amount = amount that will be taken out from senior tranche

        // TODO: What happens if Senior balance is not enough after calculating the total loan amount?
        // What kind of calculation we need to do here?

        // TODO: Will this method be called by the Remedi wallet or the our admin wallet?
        // This could be Remedi wallet as they will already have a wallet to use

        // TODO: If we were to use rUSD/USDC pool to swap rUSD to USDC, we would need to
        // check for pool balance and if there's enough liquidity to swap rUSD to USDC

        // Funds must be moved into a separate state to lock them while the loan is being processed
        // 1. Junior and Senior tranche balances must be updated
        // 2. Loan information must be stored in the LoanStorage
    }

    fun cancel_liquidity_request() {
        // This will be called by Remedi wallet
        // This will move the funds back to the tranche
    }

    fun adjust_interest_rate() {
        // Admin wallet will call this method
        // this will adjust the interest for the loan request
    }

    fun approve_interest_rate() {
        // Remedi wallet will approve the interest rate
    }

    fun approve_liquidity() {
        // Only admin wallet must be able to call this method
        // This will approve the liquidity request and move the funds to active state
        // Loan information will be stored in the LoanStorage

        // Remedi must approve the interest rate before this method can be called
    }

    fun reject_liquidity() {
        // Only admin wallet must be able to call this method
        // This will reject the liquidity request and move the funds back to the tranche
    }

    fun release_partial_loan() {
        // This method needs to swap rUSD for fiat currency
        // rUSD -> USDC -> Fiat

        // TODO: There could be a service (another contract)
        // that will take rUSD as input and swap it to USDC
        // this service will then send the USDC to on/off ramp service to convert it to fiat

        // TODO: Another option would be to send remedi wallet rUSD and use PTB to
        // send that rUSD to service that will swap it to USDC and then send it to on/off ramp service
        // instead of us doing it, we'll handle the txs from remedis wallet

        // TODO: NFT verification will be done here

        // Amount of rUSD to be swapped will be calculated based on the interest rate and duration
        // We know the full loan amount at this point

        // Transaction will have separate messages
        // Message 1: This method sends rUSD to Embedr wallet
        // Message 2: Swap rUSD to USDC through some service
        // Message 3: Send USDC to on/off ramp service
        
        // Off-chain event: Send fiat to Remedi bank account

        // 
    }

    fun repay_installment(coin: Coin<RUSD_STABLE_COIN>) {
        // TODO: This will receive what USDC?

        // Let's assume this method will get rUSD

        // Remedi will send fiat to Embedr's bank account
        // Embedr will trigger repay operation by

        // Message 1: on/off ramp service will send USDC to Embedr wallet
        // Message 2: Embedr wallet will swap USDC to rUSD through some service
        // Message 3: Embedr wallet will send rUSD to this method
        
        // Installment loan amount = 10
        // Interest amount = 1


        // Geri odenen borclarin faiz olmayan kismi ilk once senior poolu mu dolduracak? 10K borc verildiyse ilk olarak senior tranche 3K mi alacak?
        // Bu geri odenen para kullanicilarin ana tranche bakiyelerine mi eklenecek? Alinan faiz kullanicilarin "claim" edebildigi sekilde mi olacak?
    }


}
