# King of the Algo Throne 

This contract is an Algorand adaptation of [King of the Ether Throne](https://www.kingoftheether.com/thrones/kingoftheether/index.html) (KotET).

King of the Algo throne is a Ponzi scheme that follows the following rules:

- A user pays x ALGOs to the creator of the contract to become the king.
- If a user wants to become the new king, they can send double the amount of ALGOs that the previous king paid to dethrone the one that came before them.
- When a user becomes king, a curse is cast upon them: after r rounds the monarch dies, leaving the throne empty and resetting the throne claim price to the initial value x. 

## Contract state

The contract state is stored in the following global variables:

- `curse_duration` is the curse duration: the amount of time that passes between becoming king, and dying.
- `claim_price` is the amount of ALGOs that users must pay to become king
- `rate_percent` is the ratio at which the `claim_price` increases multiplied by 100
- `dethrone_fee` is the amount that users must pay to the creator of the contract in addition to the claim_price when dethroning the previous king 
- `start_amount` is the initial `claim_price`
- `curse_start` is the round at which the curse was inflicted on the current king
- `monarch` is the address of the current king
- `king_name` is the name of the current king (doesn't serve any practical purpose, it's just an extra value to memorize on the blockchain to remember the previous kings)

The variables `curse_duration`, `rate_percent`, `dethrone_fee` and `start_amount` are initialized at contract creation, and they remain constant throughout the contract lifetime. Instead, the other variables are updated every time a user becomes monarch.

## Creating a new reign

If a user is not content with the current state of the world, they might decide to create a new reign and become its king. To create a new reign however, the user must create a curse, which will be inflicted upon each and every king (including themselves). It is the duty of the creator of the reign to decide :

- how much time the curse lasts (how much time a user can live while being king) 
- how much money a user must spend to become king when the throne is vacant
- how much money every king will want to leave their position as compared to how much they spent
- their name as first king of the reign

```java
@round $curr_round
Create reign(int start_amount, int dethrone_fee, int rate_percent, int curse_duration, string king_name) {
	glob.start_amount = start_amount
	glob.dethrone_fee = dethrone_fee
	glob.rate_percent = rate_percent
	glob.curse_duration = curse_duration

	glob.claim_price = start_amount
	glob.curse_start = curr_round
	glob.monarch = caller
	glob.king_name = king_name
}
```

The `reign` function, takes 5 arguments: the `start_amount` or the amount of ALGOs that a user must spend to become king when the throne is vacant, the `dethrone_fee` or the amount of ALGOs that a user must send to the creator of the contract when dethroning a king, the `rate_percent` or how much the `claim_price` increases every time that a king gets dethroned (until a king dies), the `curse_duration` or how much time a user stays king before their death, and a `king_name`, which will be stored in the blockchain for no particular reason but to remember the names of the previous kings. 

When run, the contract stores the parameters in its global state, while also saving the address of the caller in the `monarch` variable, and initializing the `curse_start` to the current round.

## Becoming king with a vacant throne

After a monarch dies the throne becomes vacant. If a user wants to become king during this time, they have to pay a fixed fee to the creator of the reign. However, like for every other king, a curse will be inflicted upon them: if they do not get dethroned within the duration of the curse, they will die, and therefore, they will not gain any money from the next king. 

```java
@round (glob.curse_start + glob.curse_duration, )$curr_round
@pay (glob.start_amount) of ALGO : * -> creator
take_power(string king_name) {
	glob.curse_start = curr_round
	glob.monarch = caller
	glob.king_name = king_name
	glob.claim_price = (glob.start_amount * glob.rate_percent)/100
}
```

After `curse_duration` rounds since `curse_start` (when the last king came to power), it is possible to call the `take_power` function. To do so, the usermust pass as an argument the name of the new king (for example, "King Arthur IV"). They must also send a payment of `start_amount` of ALGOs to the creator of the contract.

When called, the caller becomes king, and the contract saves the round upon which the function was called, the address of the caller, the user's chosen name, and updates the claim_price, multiplying it by the `rate_percent` divided by 100.

## Dethroning a king

If some user wants to become king while the previous king is still alive, they can dethrone the current king by paying them the claim price. Once done, the user becomes monarch, and the curse is transferred to them, starting over from the round they became king.

```java
@round (, glob.curse_start + glob.curse_duration)$curr_round
@pay glob.dethrone_fee of ALGO : * -> creator
@pay glob.claim_price of ALGO : * -> glob.monarch
dethrone(string king_name) {
	glob.curse_start = curr_round
	glob.monarch = caller
	glob.king_name = king_name
	glob.claim_price = (glob.claim_price*glob.rate_percent)/100
}
```

If less than `curse_duration` rounds have passed since the `curse_start`, users will be able to call the dethrone function by passing their chosen king name, and by paying the `claim_price` to the current monarch and the `dethrone_fee` to the creator of the contract. 

Once called, similarly to the `take_power` function, the current user becomes king and the contract saves the round upon which the function was called, the address of the caller, the user's chosen name, and updates the claim_price, multiplying it by the `rate_percent` divided by 100.

## Disclaimer

The project is not audited and should not be used in a production environment.
