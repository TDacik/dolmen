
(* This file is free software, part of dolmen. See file "LICENSE" for more information *)

module Pipeline = Dolmen_loop.Pipeline.Make(State)
module Pipe = Dolmen_loop.Pipes.Make(Dolmen.Expr)(State)(State.Typer)

exception Finished of (State.t, string) result

let no_loc = Dolmen.ParseLocation.mk "" 1 1 1 1
let get_loc = function
  | Some l -> l
  | None -> no_loc
let get_decl_loc d =
  match (d : Dolmen.Statement.decl) with
  | Abstract { loc; _ }
  | Record { loc; _ }
  | Inductive { loc; _ } -> get_loc loc

let handle_exn st = function

  (* Simple error cases *)
  | Pipeline.Sigint -> Error "user interrupt"
  | Pipeline.Out_of_time -> Error "timeout"
  | Pipeline.Out_of_space -> Error "memoryout"
  (* Exn during parsing *)
  | Dolmen.ParseLocation.Uncaught (loc, exn) ->
    Error (Format.asprintf "%a: %s"
             Dolmen.ParseLocation.fmt loc (Printexc.to_string exn))

  (* lexing error *)
  | Dolmen.ParseLocation.Lexing_error (loc, msg) ->
    Ok (State.error st loc "Lexing error: %s" msg)
  (* Parsing error *)
  | Dolmen.ParseLocation.Syntax_error (loc, msg) ->
    Ok (State.error st loc "Syntax error: %s" msg)
  (* Typing error *)
  | State.Typer.T.Typing_error (Error (_env, fragment, _err) as error) ->
    let loc = get_loc (State.Typer.T.fragment_loc fragment) in
    Ok (State.error st loc "Typing error: %a" State.Typer.report_error error)

  (* File not found *)
  | State.File_not_found (l, dir, f) ->
    Ok (State.error st (get_loc l) "File not found: '%s' in directory '%s'" f dir)
  (* Input lang changed *)
  | State.Input_lang_changed _ ->
    Ok (State.error st no_loc "Language changed because of an include")

  (* Fallback *)
  | exn ->
    Ok (State.error st no_loc
          "Internal error, please report upstream: %s"
          (Printexc.to_string exn))

let finally st e =
  match e with
  | None -> st
  | Some exn ->
    let res = handle_exn st exn in
    raise (Finished res)

let process path opt_contents =
  let dir = Filename.dirname path in
  let file = Filename.basename path in
  let st = Dolmen.State.{
      debug = false;
      time_limit = 0.; (* disable the timer *)
      size_limit = max_float;
      input_dir = dir;
      input_lang = None;
      input_mode = None;
      input_source = begin match opt_contents with
        | None -> `File file
        | Some contents -> `Raw (file, contents)
      end;
      type_state = State.Typer.new_state ();
      type_check = true;
      type_infer = None;
      type_shadow = None;
      solve_state = [];
      export_lang = [];
    } in
  try
    let st, g = Pipe.parse [] st in
    let open Pipeline in
    let st = run ~finally g st (
        (fix (apply ~name:"expand" Pipe.expand) (
            (apply ~name:"typecheck" Pipe.typecheck)
            @>|> ((apply fst) @>>> _end)
          )
        )
      ) in
    Ok st
  with
  | Finished res -> res
  | exn -> handle_exn st exn

