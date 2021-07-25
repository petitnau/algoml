{
    open Parser
}

let white = [' ' '\t']+
let meol = '\n' '\n'+
let eol = '\n'
let digits = ['0'-'9'] 
let hexdigits = ['0'-'9' 'a'-'f' 'A'-'F']
let int = '-'? digits+ | '-'? "0x" hexdigits+
let letter = ['a'-'z' 'A'-'Z']
let id = (letter|'_') (letter|digits|'_')*
let str = ('"' [^'"']* '"' | '\'' [^'\'']* '\'')

rule read = 
    parse
    | white { read lexbuf }
    | meol { MEOL }
    | eol { SEOL }
    | "<=" { LEQ }
    | "<" { LT }
    | ">=" { GEQ }
    | ">" { GT }
    | "==" { EQ }
    | "!=" { NEQ }
    | "+=" { PEQ }
    | "-=" { MEQ }
    | "*=" { TEQ }
    | "/=" { DEQ }
    | "!" { NOT }
    | "+" { PLUS }
    | "-" { MINUS }
    | "*" { TIMES }
    | "/" { DIV }
    | "&&" { AND }
    | "||" { OR }
    | "@" { AT }
    | "$" { DOLLAR }
    | "->" { ARROW }
    | "(" { LPAREN }
    | ")" { RPAREN }
    | "[" { LBRACK }
    | "]" { RBRACK }
    | "{" { LBRACE }
    | "}" { RBRACE }
    | "=" { EQUALS }
    | ";" { SEMICOLON }
    | ":" { COLON }
    | "," { COMMA }
    | "." { DOT }
    | "int" { TINT }
    | "string" { TSTRING }
    | "bool" { TBOOL }
    | "token" { TTOKEN }
    | "address" { TADDRESS }
    | "assert" { ASSERT }
    | "pay" { PAY }
    | "close" { CLOSE }
    | "from" { FROM }
    | "round" { ROUND }
    | "timestamp" { TIMESTAMP }
    | "Create" { CREATE }
    | "OptIn" { OPTIN }
    | "OptOut" { OPTOUT }
    | "ClearState" { CLEARSTATE }
    | "Update" { UPDATE }
    | "Delete" { DELETE } 
    | "NoOp" { NOOP } 
    
    | "if" { IF }
    | "else" { ELSE }

    
    | "global" { GLOBAL }
    | "call" { CALL }
    | "escrow" { ESCROW }
    | "ALGO" { ALGO }

    | "mut" { MUT }
    | "glob" { GLOB }
    | "loc" { LOC }
    
    | "true" { TRUE }
    | "false" { FALSE }

    | id { IDE (Lexing.lexeme lexbuf) }
    | str { STR (Lexing.lexeme lexbuf) }
    | int { INTEGER (int_of_string(Lexing.lexeme lexbuf))}
    | eof { EOF }