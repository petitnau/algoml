exception TypeError of string
exception ErrDynamic of string
exception TmpDynamic of string
exception InitError of string
exception MutError of string
exception ParameterTypeError
exception NonOptedError
exception NonOptedTokenError of string
exception CallFail of string
exception NotEnoughFundsError of string
exception TokenAlreadyExistsError of string

type contract = Contract of decl list * aclause list
and ide = Ide of string
and decl = Declaration of statetype * muttype * vartype * ide
and parameter = Parameter of vartype * ide
and aclause = clause list
and clause =
| PayClause of pattern * pattern * pattern * pattern
| CloseClause of pattern * pattern * pattern
| TimestampClause of pattern
| RoundClause of pattern
| FromClause of pattern
| AssertClause of exp
| FunctionClause of oncomplete * ide * parameter list * cmd list 
| GStateClause of ide option * ide option
| LStateClause of exp option * ide option * ide option
| NewtokClause of pattern * ide * pattern
and exp = 
| EInt of int
| EString of string
| EBool of bool
| EToken of tok
| EAddress of address
| Val of key 
| IBop of ibop * exp * exp
| LBop of lbop * exp * exp
| CBop of cbop * exp * exp
| Not of exp
| Len of exp
| Sha256 of exp
| GetInt of exp
| Substring of exp * int * int 
| Creator
| Caller
| Escrow
and cmd = 
| Assign of key * exp
| Ifte of exp * cmd * cmd option 
| Block of cmd list
and pattern = 
| RangePattern of exp option * exp option * ide option
| FixedPattern of exp * ide option
| AnyPattern of ide option
and key = 
| GlobVar of ide
| LocVar of ide * exp option
| NormVar of ide
and vartype = TInt | TString | TBool | TToken | TAddress
and statetype = TGlob | TLoc
and muttype = Mutable | Immutable
and oncomplete = Create | NoOp | Update | Delete | OptIn | OptOut | ClearState
and ibop = Sum | Diff | Mul | Div | Mod | Bor | Band | Bxor
and lbop = And | Or
and cbop = Gt | Geq | Lt | Leq | Eq | Neq

and account = 
| UserAccount of address * balance * localenvs
| ContractAccount of address * balance * localenvs * address * contract * env
and address = Address of int
and balance = (tok * int) list
and localenvs = (address * env) list
and env = (ide * dval) list
and tok = Token of int | Algo

and state = {accounts : (address * account) list; round : int; timestamp : int}
and stateop =   
| Wait of int * int
| Transaction of transaction list
and transaction =
| PayTransaction of int * tok * address * address
| CloseTransaction of tok * address * address
| CallTransaction of address * address * oncomplete * ide * eval list
| CreateTransaction of address * contract * ide * eval list
| NewtokTransaction of int * tok * address
(* | TokOptInTransaction of tok * address *)
and opres =
| ContractAddr of address
| OpFailed
and callinfo = {caller : address; called : address; onc : oncomplete; fn : ide; params : eval list}

and eval = 
| VInt of int
| VString of string
| VBool of bool
| VToken of tok
| VAddress of address
and dval = 
| DBound of muttype * vartype * eval option
| DUnbound
