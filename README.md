# Nu http-webserver library

A nushell library to create basic webservers.

Included features:
* open http server
* parse incomming requests
* route requests to nu functions
* send response

Missing (not planned) features:
* parse request headers and body
* windows support (`mkfifo` and netcat are required)

## "Installation" / "Setup"

You can use [nupm][] or [numng][], but you will still have to install the dependencies.

1. Install all requirements
2. Download `webserver/mod.nu` as `webserver.nu`
3. `use` it in your nu scripts

Requirements:

* [nushell](https://nushell.sh) (tested with v0.95)
* [netcat](https://en.wikipedia.org/wiki/Netcat)
* [mkfifo](https://en.wikipedia.org/wiki/Named_pipe) (part of most linux coreutils)

## Usage

This is a nu library. First you have to import it (see `help use`)

### Request (data-type)

```nu
http get http://localhost/index.html?foo=bar
```

will result in the following `request` object:

```
╭──────────────┬───────────────╮
│ method       │ GET           │
│ path         │ /index.html   │
│              │ ╭─────┬─────╮ │
│ params       │ │ foo │ bar │ │
│              │ ╰─────┴─────╯ │
│ http_version │ 1.1           │
╰──────────────┴───────────────╯
```

types:

```
method: string
path: string
params: list[record[string, string?]]
http_version: string
```

### Response (data-type)

A response is a string or bytes containing a [http server response](https://en.wikipedia.org/wiki/HTTP#Server_response).

There is a function to automate the creation:

```
Usage:
  > format_http <status_code> <mime_type> <body>

Parameters:
  status_code <int>: http status code (200 means ok)
  mime_type <string>: example: text/plain
  body <string>: the actual response
```

A list of mime-types can be found [here](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Common_types).

Even shorter version:
* JSON: `application/json`
* HTML: `text/html`

In case your clients (like nushell `http get`) for whatever reason think your json is binary data you can add
`;charset=UTF-8` to the end of your mime-type (example: `application/json;charset=UTF-8`) to tell them the encoding
directly.

### Creating a mapped webserver

A mapped server automatically maps requests to the responsible nu-function
based on the path.

Example:

```nu
use webserver.nu *

# 8080 is the port the server will listen on
start_mapped_webserver 8080 {
  "/time.json": {|request|
    format_http 200 "application/json" (date now | to json)
  }
  "/hello.txt": {|request|
    format_http 200 "text/plain" $"Hello ($request.params.name? | default World)!"
  }
}
```

**Suggestion:** If you wan't to visualize / expose huge datasets with this the [stor](https://github.com/nushell/nushell/pull/11170)
command offers a really good interface for this (its accessable from anywhere, fast, etc).

### Creating a basic webserver

If you need more direct control you can use a basic webserver.

```nu
use webserver.nu *

# 8080 is the port the server will listen on
start_webserver 8080 {|request|
  let path = ($request.path | str trim --left --char "/" | path expand)
  if ($path | path type) == "file" {
    # sending everything as text/plain will cause issues with images, etc, but this is just a basic example
    format_http 200 "text/plain" (open -r $path)
  } else {
    format_http 404 "text/plain" "File not found"
  }
}
```


[nupm]: https://github.com/nushell/nupm
[numng]: https://github.com/jan9103/numng
