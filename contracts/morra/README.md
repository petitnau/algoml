# Morra game

We specify a 2-players game where the players bet 1 ALGO each, and play according to the following rules:
1. player1 and player2 join the game by paying 1 ALGO each
2. for each turn of the game:
   - both players commits to a move (a number between 1 and 5), and reveal their guesses (any number)
   - if a player guesses the sum of the two moves, then she scores 1 point
3. after the last turn, the player with the highest score can redeem the whole pot.

## Contract state

The contract state consists of the following global variables:
* `turns_to_play`: the number of turns to be played yet (mutable)
* `turn_started_at`: the round where the current turn has started
* `player1`, `player2`: the players' addresses
* `score1`,`score2`: the players' scores
* `hand_commit1`, `hand_commit2`: the hand commitments
* `hand1`, `hand2`: the players' hands
* `guess1`, `guess2`: the players' guesses
