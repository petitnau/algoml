(* open Ast  *)
(* open Format *)
(* open General *)
open Batteries

exception Error of exn * (int * int * string)

let parse () = 
  let lexbuf = Lexing.from_channel stdin in
  try
    let ast = Parser.contract Lexer.read lexbuf in 
    match ast with
    | Contract(dl, cl) ->
      Printf.printf "DL: %d CL: %d\n" (List.length dl) (List.length cl);
      print_endline (dump ast);
      ast
  with
    | exn ->
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
;;

(*ocamlbuild -use-menhir main.native && ./main.native < test*)