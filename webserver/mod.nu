use std log

export def start_mapped_webserver [
  port: int  # on which port should it listen? (8080 is a common choice)
  mappings: record  # example: {"/hello": {|request| format_http 200 "text/plain" "Hello World!"}}
  --crash-on-error  # "rethrow" errors from mappings
  --send-error-to-client  # if a mapping creates a error send a message to the web-client (warning: this might leak data)
]: nothing -> nothing {
  let handler = {|request|
    let target = ($mappings | get -i $request.path)
    if $target == null {
      format_http 404 "text/html" "<!DOCTYPE HTML><html>Endpoint is not mapped.</html>"
    } else {
      try {
        do $target $request
      } catch {|err|
        if $crash_on_error or ($err.msg =~ 'Operation interrupted') { $err.raw }  # rethrow error
        print_err $err
        format_http 300 "text/text" (if $send_error_to_client { $'[webserver.nu] handler passed to "start_mapped_webserver" at "($request.path)" created error: ($err.msg) ($err.debug?)' } else { $'Internal server error' })
      }
    }
  }
  if $crash_on_error { start_webserver $port $handler --crash-on-error } else { start_webserver $port $handler }
}


export def start_webserver [
  port: int  # on which port should it listen? (8080 is a common choice)
  request_handler: closure  # example: {|request| format_http 200 "text/plain" "Hello World"}
  --crash-on-error  # "rethrow" errors from the handler
  --send-error-to-client  # if the handler creates a error send a message to the web-client (warning: this might leak data)
]: nothing -> nothing {
  # fifo makes it possible to pipe things back into a earlier stage of the same pipeline.
  # since `nc` uses `stdin` for response and `stdout` for request this is required here.
  #
  # its not possible to mktemp a fifo or just get a path -> create a dir and put it in there instead
  let tmpdir = (mktemp -d)
  let send_fifo = $"($tmpdir)/send.fifo"
  ^mkfifo $send_fifo

  # catch crtl+c up here - otherwise it would only stop `nc` and therefore be un-exitable
  # also: it would otherwise be impossible to clean up the tmpdir (fifo, etc)
  try {
    # i was unable to find a reliable `nc` argument to prevent it from ever exiting -> restart it here whenever necesary
    loop {
      ^cat $send_fifo
      | ^nc -lN $port
      | lines
      | each {|line|
        let parsed = (
          $line
          | parse -r '^(?P<method>GET|POST|PUT|DELETE|CONNECT|OPTIONS|TRACE|PATCH) (?P<path>[^? ]*)(\?(?P<params>[^ ]+))? HTTP/(?P<http_version>[0-9.]+)$'
          | update path {|i| $i.path | url decode}
          | update params {|i|
            if ($i.params | is-empty) {
              {}
            } else {
              $i.params
              | split row "&"
              | each {|p| $p | split row "="}
              | reduce -f {} {|it,acc|
                $acc | upsert ($it.0 | url decode) (if ($it.1? == null) {null} else {$it.1 | url decode})
              }
            }
          }
          | select method path params http_version
          | get -i 0
        )
        if $parsed == null {return}  # not a request line (headers, etc instead); `each` is a bit weird -> `return` instead of `continue`
        log info $"[webserver.nu] Request: ($parsed.method) ($parsed.path)"
        try {
          do $request_handler $parsed
        } catch {|err|
          if $crash_on_error or ($err.msg =~ 'Operation interrupted') { $err.raw }  # rethrow error
          print_err $err
          format_http 300 "text/text" (if $send_error_to_client { $'[webserver.nu] handler passed to "start_webserver" created error: ($err.msg) ($err.debug?)' } else { $'Internal server error' })
        }
        | into binary  # ensure its binary (allow passing strings, etc as well)
        | save -ra $send_fifo
      }
      if $env.LAST_EXIT_CODE != 0 {break}
    }
  } catch {|err|
    rm -r $tmpdir
    if $err.msg !~ 'Operation interrupted' { $err.raw }  # rethrow error
  }
  null
}


export def format_http [
  status_code: int  # http status code (200 means ok)
  mime_type: string  # example: text/plain
  body: string  # the actual response
]: nothing -> string {
  [
    $"HTTP/1.1 ($status_code)"
    $"Content-Type: ($mime_type)"
    ""
    $body
  ] | str join "\r\n"
}

export def http_redirect [new_path: string]: nothing -> string {
  [
    "HTTP/1.1 307"
    $"Location: ($new_path)"
    "Content-Type: text/plain;charset=utf-8"
    ""
    $"Redirect to ($new_path)"
  ] | str join "\r\n"
}

def print_err [err]: nothing -> nothing {
  let mv: int = (version | get minor)
  if $mv > 100 {
    print $err.rendered
  } else if $mv < 98 {
    log error $"caught errror: ($err.msg) ($err.debug?)"
  } else {
    # since nu0.98 `tee` can error (with pretty-print) without crashing its parent-process
    # https://www.nushell.sh/blog/2024-09-17-nushell_0_98_0.html#tee-toc
    0 | tee {|| $err.raw } | null
  }
}
