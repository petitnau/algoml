open Cmdliner
open Comp
open Frontend
open Filename

let write_to_file fn content = 
  let oc = open_out fn in
  Printf.fprintf oc "%s" content;
  close_out oc

let compile infile outprefix = 
  let outprefix = (match outprefix with
  | Some(outprefix) -> outprefix
  | None -> infile |> basename |> remove_extension) in
  let ast = parse_file infile in
  let appr_prog, clear_prog, escrow_prog = comp_contract ast in
  write_to_file (outprefix^"_approval.teal") appr_prog;
  write_to_file (outprefix^"_clear.teal") clear_prog;
  match escrow_prog with
  | Some(escrow_prog) ->
    write_to_file (outprefix^"_escrow.teal") escrow_prog
  | None -> ()

let outprefix =
  let docv = "OUTPREFIX" in
  let doc = "The output file prefix." in
  Arg.(value & opt (some string) None & info ["o"; "outprefix"] ~docv ~doc)

let infile =
  let docv = "INFILE" in
  let doc = "The file to compile." in
  Arg.(required & pos 0 (some string) None & info [] ~docv ~doc )

let caml_t = Term.(const compile $ infile $ outprefix)

let info =
  let doc = "print a customizable message repeatedly" in
  let man = [
    `S Manpage.s_bugs;
    `P "Email bug reports to <roberto.pettinau99@gmail.com>." ]
  in
  Term.info "caml" ~version:"%‌%VERSION%%" ~doc ~exits:Term.default_exits ~man

let () = Term.exit @@ Term.eval (caml_t, info)