
The TEAL code of the contract is split into blocks, one per each AlgoML atomic clause. 
Each block consists of a dispatching preamble, followed by the code that implements the state update. Each atomic clause corresponds to a block. The preamble is composed of the preconditions that the clauses impose on the contract (for example the presence of a pay transaction, or an assert condition), and the state update is composed of the state update portion of the clause (for example, the new state in a @gstate clause, or the body of the function clause).
