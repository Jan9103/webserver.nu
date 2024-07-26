export def start_mapped_webserver [
  port: int  # on which port should it listen? (8080 is a common choice)
  mappings: record  # example: {"/hello": {|request| format_http 200 "text/plain" "Hello World!"}}
]: nothing -> nothing {
  start_webserver $port {|request|
    let target = ($mappings | get -i $request.path)
    if $target == null {
      format_http 404 "text/html" "<!DOCTYPE HTML><html>Endpoint is not mapped.</html>"
    } else {
      do $target $request
    }
  }
}


export def start_webserver [
  port: int  # on which port should it listen? (8080 is a common choice)
  request_handler: closure  # example: {|request| format_http 200 "text/plain" "Hello World"}
]: nothing -> nothing {
  # its not possible to mktemp a fifo or just get a path..
  let tmpdir = (mktemp -d)
  let send_fifo = $"($tmpdir)/send.fifo"
  mkfifo $send_fifo

  try {
    loop {
      cat $send_fifo
      | nc -lN $port
      | lines
      | each {|line|
        let parsed = (
          $line
          | parse -r '^(?P<method>GET|POST|PUT|DELETE|CONNECT|OPTIONS|TRACE|PATCH) (?P<path>[^? ]*)(\?(?P<params>[^ ]+))? HTTP/(?P<http_version>[0-9.]+)$'
          | update params {|i|
            if ($i.params | is-empty) {
              {}
            } else {
              $i.params
              | split row "&"
              | each {|p| $p | split row "="}
              | reduce -f {} {|it,acc| $acc | upsert $it.0 $it.1?}
            }
          }
          | select method path params http_version
          | get -i 0
        )
        if $parsed == null {return}
        print $"Request: ($parsed.method) ($parsed.path)"
        do $request_handler $parsed
        | into binary
        | bytes add --end 0x[00]
        | save -ra $send_fifo
      }
      if $env.LAST_EXIT_CODE != 0 {break}
    }
  }
  rm -r $tmpdir
  null
}


export def format_http [
  status_code: int  # http status code (200 means ok)
  mime_type: string  # example: text/plain
  body: string  # the actual response
] {
  [
    $"HTTP/1.1 ($status_code)"
    $"Content-Type: ($mime_type)"
    ""
    $body
  ] | str join "\r\n"
}
