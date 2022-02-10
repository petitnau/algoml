# Morra game

We specify a 2-players hand game where the players bet 1 ALGO each, and play according to the following rules:
1. player1 and player2 join the game by paying 1 ALGO each
2. for each turn of the game:
   - both players commit to a move (a number between 1 and 5), and to a guess (any number)
   - both players reveal their moves and guesses; failing to do so increments the other player's score
   - if a player guesses the sum of the two moves, then she scores 1 point
3. after the last turn, the player with the highest score can redeem the whole pot.

## Contract state

The contract state consists of the following global variables:
* `turns_to_play`: the number of turns to be played yet (mutable)
* `turn_started_at`: the round where the current turn has started
* `player1`, `player2`: the players' addresses
* `score1`,`score2`: the players' scores
* `hand_commit1`, `hand_commit2`: the hand commitments
* `guess_commit1`, `guess_commit2`: the guess commitments
* `hand1`, `hand2`: the players' hands
* `guess1`, `guess2`: the players' guesses

## Creating the game

The following clase is used to create the contract. The function body initialized the global state, setting `turn_started_at` at the current round, the `turns_to_play` to the value provided by the creator.

```java
@gstate -> joined0
@round $r
@assert turns_to_play > 0
Create morra(int turns_to_play) {
    glob.turns_to_play = turns_to_play
    glob.turn_started_at = r
    glob.score1 = 0
    glob.score2 = 0
}
```

## Joining the game

The following clause allows the first player to joint the game. To do so, the player just needs to pay 1 ALGO to the contract
The function body sets the `player1` variable to the caller, and the variable `turn_started_at` to the round when the clause is executed.
```java
@gstate joined0 -> joined1
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@pay 1 of ALGO : caller -> escrow
join() {
    glob.player1 = caller
    glob.turn_started_at = r
}
```

Similarly, the following clause allows the second player to join the game:
```java
@gstate joined1 -> turn1
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@pay 1 of ALGO : caller -> escrow
join() {
    glob.player2 = caller
    glob.turn_started_at = r
}
```

If the first player has not joined by the deadline, anyone can terminate the contract:
```java
@gstate joined0 -> end
@round (glob.turn_started_at+200,)
endgame() {}
```

If the second player has not joined, the first one can redeem the bet and terminate the contract:
```java
@gstate joined1 -> end
@round (glob.turn_started_at+200,)
@close ALGO : escrow -> glob.player1
endgame() {}
```

## Playing a turn

In state `turn1`, if there are still rounds to play then player1 must do her move.
A move consists in committing to a hand and to a guess.
Once the clause is executed, the number of turns to play is decremented.
```java
@gstate turn1 -> turn2
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert glob.turns_to_play > 0
hand(string hand_commit, string guess_commit) {
    glob.turns_to_play = glob.turns_to_play - 1
    glob.hand_commit1 = hand_commit
    glob.guess_commit1 = guess_commit
    glob.turn_started_at = r
}
```

In state `turn2`, player1 must do her move.
The `@assert` preconditions is needed to thwart replay attacks, where an adversary can replay a player's commits to win.
```java
@gstate turn2 -> reveal1
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert glob.hand_commit1 != hand_commit
@assert glob.guess_commit1 != guess_commit
hand(string hand_commit, string guess_commit) {
    glob.hand_commit2 = hand_commit
    glob.guess_commit2 = guess_commit
    glob.turn_started_at = r
}
```

## Opening the commitments

The following clause allows player1 to open her commitments, by revealing the hand and the guess. 
The preconditions ensure that the actual hand is a number between 0 and 5. 
To obtain the hand, we subtract 32 from the length of the committed secret `hand_commit1`: 
this ensures that the secret cannot be inferred by brute force, since its length is at least 32 bytes.
```java
@gstate reveal1 -> reveal2
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert 0 <= len(hand) - 32 && len(hand) - 32 <= 5
@assert sha256(hand) == glob.hand_commit1
@assert sha256(guess) == glob.guess_commit1
reveal(string hand, string guess) {
    glob.hand1 = len(hand) - 32
    glob.guess1 = len(guess) - 32
    glob.turn_started_at = r
}
```

Similarly, the following clause allows player2 to open her commitments. 
The `@gstate` precondition ensures that player2 can only do this after player1.
```java
@gstate reveal2 -> winturn
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert 0 <= len(hand) - 32 && len(hand) - 32 <= 5
@assert sha256(hand) == glob.hand_commit2
@assert sha256(guess) == glob.guess_commit2
reveal(string hand, string guess) {
    glob.hand2 = len(hand) - 32
    glob.guess2 = len(guess) - 32
    glob.turn_started_at = r
}
```

## Scoring the turn

The following clauses update the players' scores resulting to their moves in the current turn.
This requires to specify several clauses, since we must consider all the possible behaviours of the two players in the turn,
including those where they stop interacting with the contract.

The first clause deals with the case where player1 does not commit in time:
```java
@gstate turn1 -> turn1
@round (glob.turn_started_at+100,)$r
newturn() {
    glob.score2 += 1
    glob.turn_started_at = r
}
```

Similarly, here player2 does not commit in time:
```java
@gstate turn2 -> turn1
@round (glob.turn_started_at+100,)$r
newturn() {
    glob.score1 += 1
    glob.turn_started_at = r
}
```

The first clause deals with the case where player1 does not reveal in time:
```java
@gstate reveal1 -> turn1
@round (glob.turn_started_at+100,)$r
newturn() {
    glob.score1 += 1
    glob.turn_started_at = r
}
```

Similarly, here player2 does not commit in time:
```java
@gstate reveal2 -> turn1
@round (glob.turn_started_at+100,)$r
newturn() {
    glob.score1 += 1
    glob.turn_started_at = r
}
```

The following clause deals with the case where player1 wins the turn: this happens where player1 has guessed the sum of the two hands.
```java
@gstate winturn -> turn1
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert glob.guess1 == glob.hand1 + glob.hand2
newturn() {
    glob.score1 += 1
    glob.turn_started_at = r
}
```

Similarly, here player2 wins the turn:
```java
@gstate winturn -> turn1
@round (glob.turn_started_at,glob.turn_started_at+100)$r
@assert glob.guess2 == glob.hand1 + glob.hand2
newturn() {
    glob.score2 += 1
    glob.turn_started_at = r
}
```

Finally, if no one wins the turn, or no one claims the point, then anyone can start a new turn:
```java
@gstate winturn -> turn1
@round (glob.turn_started_at+100)$r
newturn() {
    glob.turn_started_at = r
}
```

## Closing the game
 
The following three clauses allow the winner to redeem the whole pot.
The first two preconditions of each of these clauses identify the end of the game.
Here, the winner is player1:
```java
@gstate turn1 -> end
@assert glob.turns_to_play == 0
@close ALGO : escrow -> glob.player1 
@assert glob.score1 > glob.score2
endgame() {}
```

Similarly, here the winner is player2:
```java
@gstate turn1 -> end
@assert glob.turns_to_play == 0
@close ALGO : escrow -> glob.player2
@assert glob.score2 > glob.score1
endgame() {}
```
In case of a draw, the following clause gives back 1 ALGO to each player:
```java
@gstate turn1 -> end
@assert glob.turns_to_play == 0
@assert glob.score1 == glob.score2
@pay 1 of ALGO : escrow -> glob.player1 
@pay 1 of ALGO : escrow -> glob.player2
endgame() {}
```

## Deleting the contract
 
The following clause allows the creator to delete a terminated contract:
```java
@gstate end -> 
@from creator
Delete delete() {}
```

## Disclaimer

The project is not audited and should not be used in a production environment.
