module T = Opentelemetry
let (let@) f x = f x

let sleep_inner = ref 0.1
let sleep_outer = ref 2.0
let num_sleep = ref 0

let run () =
  Printf.printf "collector is on %S\n%!" (Opentelemetry_client_ocurl.get_url());
 (* T.GC_metrics.basic_setup ();

  T.Metrics_callbacks.register (fun () ->
    T.Metrics.[ sum ~name:"num-sleep" ~is_monotonic:true [int !num_sleep] ]);
*)
  let i = ref 0 in
  while true do
    let@ scope =
      T.Trace.with_
        ~kind:T.Span.Span_kind_producer
        "loop.outer" ~attrs:["i", `Int !i] in

    for j=0 to 4 do

      let@ scope = T.Trace.with_ ~kind:T.Span.Span_kind_internal ~scope
          ~attrs:["j", `Int j]
          "loop.inner" in

      Unix.sleepf !sleep_outer;
      incr num_sleep;

      incr i;

      (try
        let@ _ =
          T.Trace.with_ ~kind:T.Span.Span_kind_internal ~scope
            "alloc" in
        (* allocate some stuff *)
        let _arr = Sys.opaque_identity @@ Array.make (25 * 25551) 42.0 in
        ignore _arr;

        Unix.sleepf !sleep_inner;
        incr num_sleep;

        if j=4 && !i mod 13 = 0 then failwith "oh no"; (* simulate a failure *)

        T.Trace.add_event scope (fun () -> T.Event.make "done with alloc");
      with Failure _ ->
        ());
    done;
  done

let () =
  Sys.catch_break true;
  T.Globals.service_name := "newrelic_reporter";
  T.Globals.service_namespace := Some "ocaml-otel.test";

  let debug = ref false in
  let thread = ref true in
  let batch_traces = ref 400 in
  let batch_metrics = ref 0 in
  let opts = [
    "--debug", Arg.Bool ((:=) debug), " enable debug output";
    "--thread", Arg.Bool ((:=) thread), " use a background thread";
    "--batch-traces", Arg.Int ((:=) batch_traces), " size of traces batch";
    "--batch-metrics", Arg.Int ((:=) batch_metrics), " size of metrics batch";
    "--sleep-inner", Arg.Set_float sleep_inner, " sleep (in s) in inner loop";
    "--sleep-outer", Arg.Set_float sleep_outer, " sleep (in s) in outer loop";
  ] |> Arg.align in

  Arg.parse opts (fun _ -> ()) "emit1 [opt]*";

  let some_if_nzero r = if !r > 0 then Some !r else None in
  let config = Opentelemetry_client_ocurl.Config.make
      ~debug:!debug
      ~batch_traces:(some_if_nzero batch_traces)
      ~batch_metrics:(some_if_nzero batch_metrics)
      ~thread:!thread () in
  Format.printf "@[<2>sleep outer: %.3fs,@ sleep inner: %.3fs,@ config: %a@]@."
    !sleep_outer !sleep_inner Opentelemetry_client_ocurl.Config.pp config;

  Opentelemetry_client_ocurl.with_setup ~config () run
