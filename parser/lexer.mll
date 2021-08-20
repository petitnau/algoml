{
    open Parser
    let string_buff = Buffer.create 256
}

let white = [' ' '\t']+
let eol = (white* '\n' white* | white* "\r\n" white*)
let meol = eol eol+
let digits = ['0'-'9'] 
let hexdigits = ['0'-'9' 'a'-'f' 'A'-'F']
let int = '-'? digits+ | '-'? "0x" hexdigits+
let letter = ['a'-'z' 'A'-'Z']
let id = (letter|'_') (letter|digits|'_')*

rule linecomment mnl =
    parse
    | meol { MEOL }
    | eol { if mnl then MEOL else SEOL}
    | _  {linecomment mnl lexbuf }
and multicomment = 
    parse
    | "*/" { read lexbuf }
    | _ { multicomment lexbuf }
and string = 
    parse
    | '"' { () }
    | "\\\"" { Buffer.add_char string_buff '"' }
    | _ as c { Buffer.add_char string_buff c; string lexbuf }
and read = 
    parse
    | white { read lexbuf }
    | meol { MEOL } 
    | eol { SEOL }
    | meol "//" { linecomment true lexbuf }
    | eol? "//" { linecomment false lexbuf }
    | '"' { Buffer.clear string_buff; string lexbuf; STR (Buffer.contents string_buff)}
    | "/*" { multicomment lexbuf }
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
    | "gstate" { GSTATE }
    | "lstate" { LSTATE }
    | "pay" { PAY }
    | "close" { CLOSE }
    | "from" { FROM }
    | "round" { ROUND }
    | "timestamp" { TIMESTAMP }
    | "newtok" { NEWTOK }
    | "Create" { CREATE }
    | "OptIn" { OPTIN }
    | "OptOut" { OPTOUT }
    | "ClearState" { CLEARSTATE }
    | "Update" { UPDATE }
    | "Delete" { DELETE } 
    | "NoOp" { NOOP } 
    
    | "of" { OF }

    | "if" { IF }
    | "else" { ELSE }

    
    | "creator" { CREATOR }
    | "caller" { CALLER }
    | "escrow" { ESCROW }
    | "ALGO" { ALGO }

    | "mut" { MUT }
    | "glob" { GLOB }
    | "loc" { LOC }
    
    | "true" { TRUE }
    | "false" { FALSE }

    | id { IDE (Lexing.lexeme lexbuf) }
    | int { INTEGER (int_of_string(Lexing.lexeme lexbuf))}
    | eof { EOF }