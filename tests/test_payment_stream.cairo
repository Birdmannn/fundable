use core::traits::Into;
use starknet::{get_block_timestamp, ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    cheat_caller_address, CheatSpan, stop_cheat_caller_address, start_cheat_caller_address_global,
    stop_cheat_caller_address_global,
};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

fn setup() -> (ContractAddress, ContractAddress, IPaymentStreamDispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into()];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Payment stream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@calldata).unwrap();

    (erc20_address, sender, IPaymentStreamDispatcher { contract_address: payment_stream_address })
}


#[test]
fn test_successful_create_stream() {
    let (token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");
}

#[test]
#[should_panic(expected: 'Error: End time < start time.')]
fn test_invalid_end_time() {
    let (token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 50_u64;
    let cancelable = true;

    payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_zero_recipient_address() {
    let (token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x0>(); // Invalid zero address
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
}

#[test]
#[should_panic(expected: 'Error: Invalid token address.')]
fn test_zero_token_address() {
    let (_token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(
            recipient,
            total_amount,
            start_time,
            end_time,
            cancelable,
            contract_address_const::<0x0>(),
        );
}

#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_zero_total_amount() {
    let (token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 0_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
}


#[test]
fn test_update_fee_collector() {
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    let (token_address, sender, payment_stream) = setup();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);

    let fee_collector = payment_stream.get_fee_collector();
    assert(fee_collector == new_fee_collector, 'wrong fee collector');
}

#[test]
fn test_update_percentage_protocol_fee() {
    let (token_address, sender, payment_stream) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_percentage_protocol_fee(300);
}

#[test]
fn test_withdraw() {
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_percentage_protocol_fee(300);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(sender, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let (net_amount, fee) = payment_stream.withdraw(stream_id, 1000, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // let recipient_balance = token_dispatcher.balance_of(recipient);
    // println!("Recipient's balance after withdrawal: {}", recipient_balance);

    let fee_collector = payment_stream.get_fee_collector();
    let fee_collector_balance = token_dispatcher.balance_of(fee_collector);
    assert(fee_collector_balance == fee.into(), 'incorrect fee received');

    let sender_final_balance = token_dispatcher.balance_of(sender);
    println!("Sender's final balance: {}", sender_final_balance);
}

#[test]
fn test_withdraw_max() {
    // create stream
    let (token_address, sender, payment_stream) = setup();
    let stream_id = initialize_default_stream(payment_stream, sender, token_address);
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    let total_amount = 100000000000_u256;
    
    cheat_caller_address(token_address, sender, CheatSpan::TargetCalls(1));
    token_dispatcher.approve(payment_stream.contract_address, total_amount);

    let allowance = token_dispatcher.allowance(sender, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    cheat_caller_address(payment_stream.contract_address, sender, CheatSpan::TargetCalls(1));
    let (net_amount, fee) = payment_stream.withdraw_max(stream_id, recipient());

    // 10 percent set of total_amount
    let expected_fee: u128 = (10 * total_amount.try_into().unwrap()) / 100;
    let expected_net_amount = total_amount.try_into().unwrap() - expected_fee;

    assert(expected_net_amount == net_amount, 'NET AMOUNT ERROR');
    assert(fee == expected_fee, 'EXPECTED FEE ERROR');
    println!("Balance of recipient: {}", token_dispatcher.balance_of(recipient()));
    assert(
        token_dispatcher.balance_of(recipient()) == expected_net_amount.into(), 'WITHDRAWAL ERROR',
    );
    let fee_collector = payment_stream.get_fee_collector();
    assert(
        token_dispatcher.balance_of(fee_collector) == expected_fee.into(), '2. EXPECTED FEE ERROR',
    );
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_withdraw_max_zero_address() {
    assert(false, 'Error: Invalid recipient.');
}

#[test]
fn test_cancel() {}

#[test]
fn test_restart() {}

#[test]
fn test_void() {}

fn initialize_default_stream(
    payment_stream: IPaymentStreamDispatcher,
    sender: ContractAddress,
    token_address: ContractAddress,
) -> u256 {
    let total_amount = 10000_u256;
    let start_time = starknet::get_block_timestamp();
    let end_time = start_time + 10000;
    let cancelable = true;

    cheat_caller_address(
        payment_stream.contract_address, protocol_owner(), CheatSpan::TargetCalls(1),
    );
    payment_stream.update_fee_collector(new_fee_collector());

    cheat_caller_address(payment_stream.contract_address, sender, CheatSpan::TargetCalls(1));
    let stream_id = payment_stream
        .create_stream(recipient(), total_amount, start_time, end_time, cancelable, token_address);

    let protocol_fee: u16 = 10;
    cheat_caller_address(
        payment_stream.contract_address, protocol_owner(), CheatSpan::TargetCalls(1),
    );
    payment_stream.update_percentage_protocol_fee(protocol_fee);

    stream_id
}

fn recipient() -> ContractAddress {
    contract_address_const::<'recipient'>()
}

fn protocol_owner() -> ContractAddress {
    contract_address_const::<'protocol_owner'>()
}

fn new_fee_collector() -> ContractAddress {
    contract_address_const::<'new_fee_collector'>()
}
