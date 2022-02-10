%{
  open Types
%}

%token EOF
%token SEOL
%token MEOL

%token GEQ
%token GT
%token LEQ
%token LT
%token EQ
%token NEQ

%token PEQ
%token MEQ
%token TEQ
%token DEQ

%token NOT
%token OR
%token AND

%token PLUS
%token MINUS
%token TIMES
%token DIV
%token MOD
%token AT
%token DOLLAR
%token ARROW
%token LPAREN
%token RPAREN
%token LBRACE
%token RBRACE
%token LBRACK
%token RBRACK
%token EQUALS
%token SEMICOLON
%token COLON
%token COMMA
%token DOT

%token LEN
%token SHA256
%token GETINT
%token SUBSTRING

%token TRUE
%token FALSE

%token TINT
%token TSTRING
%token TBOOL
%token TTOKEN
%token TADDRESS

%token MUT

%token GSTATE
%token LSTATE
%token PAY
%token CLOSE
%token FROM
%token ROUND
%token TIMESTAMP
%token ASSERT
%token NEWTOK

%token OF

%token CREATE
%token OPTIN
%token OPTOUT
%token CLEARSTATE
%token UPDATE
%token DELETE
%token NOOP

%token IF
%token ELSE

%token GLOB
%token LOC

%token CREATOR
%token CALLER
%token ESCROW
%token ALGO

%token <int> INTEGER
%token <string> IDE
%token <string> STR

%left OR
%left AND
%left GEQ GT LEQ LT EQ NEQ
%left PLUS MINUS 
%left TIMES DIV
%left MOD
%right NOT


%start <Types.contract> contract

%%

optterm_list(separator, X):
  | separator? {[]}
  | l=optterm_nonempty_list(separator, X) { l } 
optterm_nonempty_list(separator, X):
  | x = X separator? { [ x ] }
  | x = X
    separator
    xs = optterm_nonempty_list(separator, X)
     { x :: xs }

meol:
| MEOL; eols*; {}

contract:
| eols?; dl = optterm_list(eols, declaration); cl = optterm_list(meol, aclause); eols?; EOF{ Contract(dl, cl) }

declaration: 
| s=statetype; m=muttype; t=vartype; i=ide; { Declaration(s,m,t,i) }

muttype:
| MUT; { Mutable }
| (* epsilon *) { Immutable }

statetype:
| GLOB; { TGlob }
| LOC; { TLoc }
// | (* epsilon *) { TNorm }

vartype:
| TINT; { TInt }
| TSTRING; { TString }
| TBOOL; { TBool }
| TTOKEN; { TToken }
| TADDRESS; { TAddress }

aclause: 
| cl = optterm_nonempty_list(SEOL+, clause) { cl }

clause:
| AT; GSTATE; sf=option(ide); st=endstate { GStateClause(sf, st) }
| AT; LSTATE; sf=option(ide); st=endstate { LStateClause(None, sf, st) }
| AT; LSTATE; LBRACK; e=exp; RBRACK; sf=option(ide); st=endstate { LStateClause(Some(e), sf, st) }
| AT; PAY; amt_p=pattern; OF; tkn_p=pattern; COLON; xfr_p=pattern; ARROW; xto_p=pattern; { PayClause(amt_p, tkn_p, xfr_p, xto_p) }
| AT; PAY; amt_p=pattern; OF; ALGO; COLON; xfr_p=pattern; ARROW; xto_p=pattern; { PayClause(amt_p, FixedPattern(EToken(Algo), None), xfr_p, xto_p) }
| AT; PAY; amt_p=pattern; COLON; xfr_p=pattern; ARROW; xto_p=pattern; { PayClause(amt_p, FixedPattern(EToken(Algo), None), xfr_p, xto_p) }
| AT; PAY; xfr_p=pattern; ARROW; xto_p=pattern; { PayClause(AnyPattern(None), FixedPattern(EToken(Algo), None), xfr_p, xto_p) }
| AT; CLOSE; tkn_p=pattern; COLON; xfr_p=pattern; ARROW; xto_p=pattern; { CloseClause(tkn_p, xfr_p, xto_p) }
| AT; CLOSE; ALGO; COLON; xfr_p=pattern; ARROW; xto_p=pattern; { CloseClause(FixedPattern(EToken(Algo), None), xfr_p, xto_p) }
| AT; CLOSE; xfr_p=pattern; ARROW; xto_p=pattern; { CloseClause(FixedPattern(EToken(Algo), None), xfr_p, xto_p) }
| AT; TIMESTAMP; p=pattern; { TimestampClause(p) }
| AT; ROUND; p=pattern; { RoundClause(p) }
| AT; FROM; p=pattern; { FromClause(p) }
| AT; ASSERT; e=exp; { AssertClause(e) }
| AT; NEWTOK; amt_p=pattern; OF; DOLLAR; i=ide; ARROW; xto_p=pattern; { NewtokClause(amt_p, i, xto_p) }
| AT; NEWTOK; DOLLAR; i=ide; ARROW; xto_p=pattern; { NewtokClause(FixedPattern(EInt(max_int), None), i, xto_p) }
| fc=functionclause; { fc }

endstate:
| ARROW; st=option(ide) { st }
| (* epsilon *) { None }

state:
| GSTATE; { TGlob }
| LSTATE; { TLoc }

pattern:
| LPAREN; e1=option(exp); COMMA; e2=option(exp); RPAREN; i=bind { RangePattern(e1, e2, i) }
| e=exp; i=bind { FixedPattern(e, i) }
| TIMES; i=bind { AnyPattern(i) }
| (* epsilon; *) i=bind { AnyPattern(i) }

bind:
| (* epsilon *) { None }
| DOLLAR; i=ide { Some(i) }

functionclause:
| onc=oncomplete; i=ide; LPAREN; pl = separated_list(COMMA, parameter); RPAREN; cl = funblock; { FunctionClause(onc, i, pl, cl) }

oncomplete:
| CREATE { Create }
| OPTIN { OptIn }
| OPTOUT { OptOut }
| CLEARSTATE { ClearState }
| UPDATE { Update }
| DELETE { Delete }
| NOOP { NoOp }
| (* epsilon *) { NoOp }

ide: 
| i=IDE; { Ide(i) }

parameter:
| eols?; t=vartype; i=IDE; eols?; { Parameter(t,Ide(i)) }

funblock:
| eols?; LBRACE; eols?; cl = optterm_list(eols, cmd); RBRACE; { cl }

block:
| eols?; LBRACE; eols?; cl = optterm_list(eols, cmd); RBRACE; eols? { cl }

eols:
| SEOL; eols* { () }
| MEOL; eols* { () }

cmd:
| cl=block; { Block(cl) }
| k=key; EQUALS; e=exp; { Assign(k, e) }
| k=key; PEQ; e=exp; { Assign(k, IBop(Sum, Val(k), e)) }
| k=key; MEQ; e=exp; { Assign(k, IBop(Diff, Val(k), e)) }
| k=key; TEQ; e=exp; { Assign(k, IBop(Mul, Val(k), e)) }
| k=key; DEQ; e=exp; { Assign(k, IBop(Div, Val(k), e)) }
| IF; LPAREN; e=exp; RPAREN; c1=cmd; ELSE; c2=cmd; { Ifte(e, c1, Some c2) }
| IF; LPAREN; e=exp; RPAREN; c1=cmd; { Ifte(e, c1, None) }

exp:
| LEN; LPAREN; e=exp; RPAREN { Len(e) }
| SHA256; LPAREN; e=exp; RPAREN { Sha256(e) }
| GETINT; LPAREN; e=exp; RPAREN { GetInt(e) }
| SUBSTRING; LPAREN; e=exp; COMMA; f=INTEGER; COMMA; t=INTEGER; RPAREN { Substring(e, f, t) }
| LPAREN; e=exp; RPAREN { e }
| n=INTEGER; { EInt(n) }
| s=STR; { EString(s) }
| TRUE; { EBool(true) }
| FALSE; { EBool(false) }
(*| token *)
(*| address *)
| k=key; { Val(k) }
| e1=exp; PLUS; e2=exp; { IBop(Sum, e1, e2) }
| e1=exp; MINUS; e2=exp; { IBop(Diff, e1, e2) }
| e1=exp; TIMES; e2=exp; { IBop(Mul, e1, e2) }
| e1=exp; DIV; e2=exp; { IBop(Div, e1, e2) }
| e1=exp; MOD; e2=exp; { IBop(Mod, e1, e2) }
| e1=exp; AND; e2=exp; { LBop(And, e1, e2) }
| e1=exp; OR; e2=exp; { LBop(Or, e1, e2) }
| e1=exp; GT; e2=exp; { CBop(Gt, e1, e2) }
| e1=exp; GEQ; e2=exp; { CBop(Geq, e1, e2) }
| e1=exp; LT; e2=exp; { CBop(Lt, e1, e2) }
| e1=exp; LEQ; e2=exp; { CBop(Leq, e1, e2) }
| e1=exp; EQ; e2=exp; { CBop(Eq, e1, e2) }
| e1=exp; NEQ; e2=exp; { CBop(Neq, e1, e2) }
| NOT; e=exp; { Not(e) }

| CREATOR; { Creator }
| CALLER; { Caller }
| ESCROW; { Escrow }

key:
| i=ide; { NormVar(i) }
| GLOB; DOT; i=ide; { GlobVar(i) }
| LOC; DOT; i=ide; { LocVar(i,None) }
| e=exp; DOT; i=ide; { LocVar(i,Some(e)) }
