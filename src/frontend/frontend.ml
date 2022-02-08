open Static

exception Error of exn * (int * int * string)

let parse_buf (lexbuf:Lexing.lexbuf) = 
  try
    let ast = Parser.contract Lexer.read lexbuf in 
    check_program ast;
    if not(check_aclauses_funcclause ast) then failwith "Not all atomic clauses have one function clause"
    else if not(check_create_in_contract ast) then failwith "Incorrect amount of create clauses"
    else if not(check_duplicates ast) then failwith "Duplicate glob ides or loc ides"
    else if not(check_reachable_states ast) then failwith "Not all states are reachable"
    else ast
  with
    | Parser.Error as exn -> 
    begin
      let curr = lexbuf.Lexing.lex_curr_p in
      let line = curr.Lexing.pos_lnum in
      let cnum = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in
      let tok = Lexing.lexeme lexbuf in
      print_string "Parser.Error: ";
      print_int line;
      print_string " ";
      print_int cnum;
      print_string " ";
      print_endline ("'"^tok^"'");
      raise (Error (exn,(line,cnum,tok)))
    end

let parse_input () = 
  let lexbuf = Lexing.from_channel stdin in
  parse_buf lexbuf
    
let parse_file (filename:string) = 
  let f = open_in filename in
  let lexbuf = Lexing.from_channel f in
  parse_buf lexbuf

let parse_string (s:string) = 
  let lexbuf = Lexing.from_string s in
  parse_buf lexbuf