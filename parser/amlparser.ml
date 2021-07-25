(* open Ast  *)
(* open Format *)
(* open General *)
open Batteries
open Static

exception Error of exn * (int * int * string)

let parse_buf (lexbuf:Lexing.lexbuf) = 
  try
    let ast = Parser.contract Lexer.read lexbuf in 
    (* match ast with
    | Contract(dl, cl) -> *)
      (* Printf.printf "DL: %d CL: %d\n" (List.length dl) (List.length cl); *)
      (* print_endline (dump ast); *)
    let types = check_program ast in
    if types = None then raise TypeError
    else ast
  with
    | Parser.Error as exn -> 
    begin
      let curr = lexbuf.Lexing.lex_curr_p in
      let line = curr.Lexing.pos_lnum in
      let cnum = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in
      let tok = Lexing.lexeme lexbuf in
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

(*ocamlbuild -use-menhir main.native && ./main.native < test*)