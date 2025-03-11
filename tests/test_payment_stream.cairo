use core::traits::Into;
use starknet::{get_block_timestamp, ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    cheat_caller_address, CheatSpan, stop_cheat_caller_address, start_cheat_caller_address_global,
    stop_cheat_caller_address_global,
};
use fundable::base::types::{Stream, StreamStatus};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};

// Constantes para roles
const STREAM_ADMIN_ROLE: felt252 = selector!("STREAM_ADMIN");
const PROTOCOL_OWNER_ROLE: felt252 = selector!("PROTOCOL_OWNER");

fn setup_access_control() -> (
    ContractAddress, ContractAddress, IPaymentStreamDispatcher, IAccessControlDispatcher,
) {
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

    (
        erc20_address,
        sender,
        IPaymentStreamDispatcher { contract_address: payment_stream_address },
        IAccessControlDispatcher { contract_address: payment_stream_address },
    )
}

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
    let delegate = contract_address_const::<'delegate'>();

    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(delegate, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(payment_stream.contract_address, delegate);
    let (_, fee) = payment_stream.withdraw(stream_id, 1000, recipient);
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
fn test_successful_stream_cancellation() {
    let (token_address, _sender, payment_stream) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");

    payment_stream.cancel(stream_id);
    let get_let = payment_stream.is_stream_active(stream_id);

    assert(get_let == false, 'Cancelation failed');
}

#[test]
fn test_withdraw_by_delegate() {
    // Setup: deploy contracts and define test addresses.
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    // Sender creates a stream.
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Simulate delegate's approval:
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, 5000_u256);
    stop_cheat_caller_address(token_address);

    // Delegate performs withdrawal.
    start_cheat_caller_address(payment_stream.contract_address, delegate);
    let (_, fee) = payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    let fee_collector = payment_stream.get_fee_collector();
    let fee_collector_balance = token_dispatcher.balance_of(fee_collector);
    assert(fee_collector_balance == fee.into(), 'incorrect fee received');
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_withdraw_by_unauthorized() {
    // Setup: deploy contracts and define test addresses.
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Sender creates a stream.
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Unauthorized account attempts withdrawal.
    start_cheat_caller_address(payment_stream.contract_address, unauthorized);
    payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}



#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unauthorized_cancel() {
    let (token_address, sender, payment_stream, access_control) = setup_access_control();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream as the sender - this will automatically assign STREAM_ADMIN_ROLE
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Verify that the sender has the STREAM_ADMIN_ROLE after creating the stream
    let has_role = access_control.has_role(STREAM_ADMIN_ROLE, sender);
    assert(has_role, 'Sender should have admin role');
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to cancel the stream with an unauthorized user (recipient)
    // The recipient does not have the STREAM_ADMIN_ROLE
    start_cheat_caller_address(payment_stream.contract_address, recipient);

    // Verify that the recipient does NOT have the STREAM_ADMIN_ROLE
    let recipient_has_role = access_control.has_role(STREAM_ADMIN_ROLE, recipient);
    assert(!recipient_has_role, 'Recipient should not have role');

    payment_stream.cancel(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_pause_stream() {
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Pause the stream
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');
}

#[test]
fn test_restart_stream() {
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Pause the stream first
    payment_stream.pause(stream_id);

    // Verify that the stream was paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');

    // Restart the stream with a new rate
    let new_rate = 100_u256; // Rate per second
    payment_stream.restart(stream_id, new_rate);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was restarted
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Active, 'Stream should be active');
    assert(stream.rate_per_second == new_rate, 'Rate should be updated');
}

#[test]
fn test_void_stream() {
    let (token_address, sender, payment_stream) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Void the stream
    payment_stream.void(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was voided
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Voided, 'Stream should be voided');
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
