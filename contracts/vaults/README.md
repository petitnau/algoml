# Algorand vaults

Vaults are a security mechanism to prevent cryptocurrency from being immediately withdrawn. When users want to withdraw some crypto from a vault, they must first issue a request, and the withdrawal is finalized only after a certain wait time has passed since the request. During the wait time, the request can be cancelled by using a recovery key. Vaults mitigate the risk that the user's private key is stolen: whenever an adversary attempts to withdraw using a stolen private key, the legit user can cancel the operation through the recovery key.

Vaults are quite popular in blockchain ecosystems. For instance, they are available on the following crypto wallets:
* [Coinbase](https://help.coinbase.com/en/coinbase/getting-started/other/vaults-faq)
* [Bitcoin Suisse](https://www.bitcoinsuisse.com/vault)
* [Electrum Vault](https://github.com/bitcoinvault/electrum-vault)

The purpose of this tutorial is to create a **decentralized** vault as an Algorand smart contract.

## Table of contents
- [Algorand vaults](#algorand-vaults)
  - [Table of contents](#table-of-contents)
  - [Contract state](#contract-state)
  - [Creating the vault](#creating-the-vault)
  - [Depositing funds](#depositing-funds)
  - [Requesting a withdrawal](#requesting-a-withdrawal)
  - [Finalizing a request](#finalizing-a-request)
  - [Cancelling a request](#cancelling-a-request)
- [Disclaimer](#disclaimer)
- [Credits](#credits)

## Contract state

The contract state is stored in the following variables:

* `wait_time` is the withdrawal wait time, i.e. the number of rounds that must pass between a withdrawal request and its finalization
* `recovery` is the address from which the cancel action must originate
* `request_time` is the round at which the withdrawal request has been submitted
* `amount` is the amount of algos to be withdrawn
* `receiver` is the address which can withdraw the algos
* `gstate` is the contract state: 
  * `waiting`: there is no pending withdrawal request
  * `requested`: there is a pending withdrawal request

The variables `wait_time`, `recovery` are initialized at contract creation, and they remain constant throughout the contract lifetime. Instead, the other variables are updated upon each withdrawal request.

## Creating the vault

Any user can create a vault, providing the recovery address and the withdrawal wait time. 

We specify the behaviour of this action in AlgoML as follows:
```java
@gstate ->waiting
Create vault(address recovery, int wait_time) {
    glob.recovery = recovery
    glob.wait_time = wait_time
}
```
The `Create` modifier implies that this function actually constructs the contract. The function has two parameters: the `recovery` address, and the withdrawal `wait_time`. The body of the function just initializes the two global state variables `recovery` and `wait_time`.
The clause 
```java
@gstate ->waiting
```
means that after the action is performed, the new state of the contract is `waiting`.

## Depositing funds 

Any user can deposit algos into the vault. Since paying algos to an account cannot be constrained in Algorand, this part of the specification is given by default, so it does not require a specific clause in AlgoML. 

## Requesting a withdrawal

Once the contract is created and the escrow connected to the contract, the vault creator can request a withdrawal. This requires the creator to declare the `amount` of algos to be withdrawn, and the address of the `receiver`. The contract stores these values, as well as the round when the withdrawal is requested. This is specified in AlgoML as follows:

```java
@gstate waiting->requested
@round $curr_round
@from creator
withdraw(int amount, address receiver) {
    glob.amount = amount
    glob.receiver = receiver
    glob.request_time = curr_round
}
```
The `withdraw` function can only be called by the creator, and only while the contract is in the `waiting` state. The function body saves the values of the parameters and the current round in the contract state. The precondition `@gstate waiting->requested` also ensures that the next state will be `requested`, while `@round $curr_round` binds the current round to the `curr_round` identifier. Note that we do *not* require that the vault contains at least `amount` algos: indeed, this is not strictly necessary, as the creator can fund the vault after the request has been made.

## Finalizing a request

After the withdrawal wait period has passed, the vault creator can finalize the request, thus releasing the funds to the specified address, and taking the contract back to a state where it waits for another request.

```java
@gstate requested->waiting
@round (glob.request_time + glob.wait_time,)
@from creator
@pay glob.amount : escrow -> glob.receiver
finalize() { }
```

The `finalize` function can only be called by the vault creator, provided that the current state is `requested` and `wait_time` rounds have passed since the `requested_time`. Further, the precondition:
```java
@pay glob.amount : escrow -> glob.receiver
```
requires that the function call is bundled with a pay transaction that transfers the amount of algos specified in the request from the vault to the declared receiver. After the function call, the contract state is set to `waiting`.

## Cancelling a request 

The vault creator can abort an unexpected withdrawal (which probably means that someone knows the private key of the creator). This is done by calling the `cancel` function, which aborts the current withdrawal request. Since this action requires to know the private key of the *recovery* account, an adversary who knows only the private key of the vault creator will not be able to abort the withdrawal requests.

```java
@gstate requested->waiting
@from glob.recovery
cancel() { }
```

The preconditions ensure that the function is called from the recovery address, and only when the contract is in the `requested` state. After the call, the contract will return to the `waiting` state, thus disabling the `finalize` function.

## Disclaimer

The project is not audited and should not be used in a production environment.
