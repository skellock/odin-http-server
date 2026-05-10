package server

import http "./odin-http"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

Options :: struct {
	port: int `usage:"Which port to listen on. (default: 8080)"`,
}

opt: Options
server: http.Server
router: http.Router

// entry point
main :: proc() {
	configure_arguments()

	http.router_init(&router)
	configure_routes()
	defer http.router_destroy(&router)

	serve()
}

// read the command line arguments
configure_arguments :: proc() {
	flags.parse_or_exit(&opt, os.args, .Unix)

	if opt.port <= 0 {
		opt.port = 8080
	}
}

// setup the router
configure_routes :: proc() {
	// odinfmt: disable
	http.route_get  ( &router, "/url",                http.handler(url)         )
	http.route_get  ( &router, "/params/(%w+)/(%w+)", http.handler(url_params)  )
	http.route_get  ( &router, "/headers",            http.handler(headers)     )
	http.route_get  ( &router, "/html",               http.handler(html_file)   )
	http.route_get  ( &router, "/inline",             http.handler(inline_html) )
	http.route_get  ( &router, "/ip",                 http.handler(ip)          )
	http.route_get  ( &router, "/up",                 http.handler(up)          )
	http.route_get  ( &router, "/mem",                http.handler(memory)      )
	http.route_get  ( &router, "/now",                http.handler(now)         )
	http.route_get  ( &router, "/json",               http.handler(json_output) )
	http.route_post ( &router, "/count",              http.handler(count)       )
	http.route_post ( &router, "/echo",               http.handler(echo)        )
	http.route_post ( &router, "/form",               http.handler(form)        )
	http.route_get  ( &router, "(.*)",                http.handler(static)      )
	// odinfmt: enable
}

// fire up the server and listen
serve :: proc() {
	http.server_shutdown_on_interrupt(&server)

	// try to listen
	endpoint := net.Endpoint{net.IP4_Any, opt.port}
	listen_err := http.listen(&server, endpoint)

	if listen_err != nil {
		switch listen_err {
		case net.Bind_Error.Insufficient_Permissions_For_Address:
			fmt.printf("Error: insufficient permissions to listen on port %d\n", endpoint.port)
			if endpoint.port < 1024 {
				fmt.printf("Error: root user is required to listen on ports 1-1023\n")
			}

		case net.Bind_Error.Address_In_Use:
			fmt.printf("Error: port %d is being used by another process.\n", endpoint.port)

		case:
			fmt.printf("Error: %v\n", listen_err)
		}
		return
	}

	// try to serve
	fmt.printf("Listening on :%d\n", endpoint.port)
	root_handler := http.router_handler(&router)
	serve_err := http.serve(&server, root_handler)

	if serve_err != nil {
		fmt.printf("Error %v\n", listen_err)
	}
}

// =--- Handlers Start Here --------------------------------------------------->

url :: proc(req: ^http.Request, res: ^http.Response) {
	sb := strings.builder_make(context.temp_allocator)

	fmt.sbprintf(&sb, "path        = %v\n", req.url.path)
	fmt.sbprintf(&sb, "query       = %v\n", req.url.query)
	fmt.sbprintf(&sb, "host header = %v\n", http.headers_get(req.headers, "host"))

	http.respond_plain(res, strings.to_string(sb))
}

// Show the url parameters
url_params :: proc(req: ^http.Request, res: ^http.Response) {
	sb := strings.builder_make(context.temp_allocator)

	fmt.sbprintf(&sb, "url params:\n\n")
	if len(req.url_params) <= 0 {
		fmt.sbprintf(&sb, "No url parameters")
	} else {
		for header in req.url_params {
			fmt.sbprintf(&sb, "  %v\n", header)
		}
	}

	http.respond_plain(res, strings.to_string(sb))
}

// Show the request parameters
headers :: proc(req: ^http.Request, res: ^http.Response) {
	sb := strings.builder_make(context.temp_allocator)

	fmt.sbprintf(&sb, "Request Headers:\n\n")
	for header in req.headers._kv {
		fmt.sbprintf(&sb, "%v = %v\n", header, http.headers_get(req.headers, header))
	}

	http.respond_plain(res, strings.to_string(sb))
}

// A static directory fallback for all requests
static :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_dir(res, "/", "public", req.url_params[0])
}

// An HTML file on the filesystem with a MIME type.
html_file :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_file(res, "public/fun.html", .Html)
}

// Inline
inline_html :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(
		res,
		"<html><head><title>HELLO TITLE</title></head><body><h1>OMG HAI!</h1><p>Hello <b>Liam</b></p></body></html>",
	)
}

// Shows the IP address of the request.
ip :: proc(req: ^http.Request, res: ^http.Response) {
	remote_ip := net.address_to_string(req.client.address, context.temp_allocator)
	http.respond_plain(res, remote_ip)
}

// Returns just a 200 status.
up :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_with_status(res, .OK)
}

// Shows the peak memory used by the temp allocator.
memory :: proc(req: ^http.Request, res: ^http.Response) {
	temp_arena := (^mem.Arena)(context.temp_allocator.data)
	content := fmt.tprintf(
		"temp allocator peak bytes used = %f mb",
		f64(temp_arena.peak_used) / 1024.0 / 1024.0,
	)
	http.respond_html(res, content)
}

// Prints the server's time (1-sec interval) and the request time in rfc3339.
now :: proc(req: ^http.Request, res: ^http.Response) {
	server_date := string(server.date.buf_backing[:])
	real_date := time.time_to_rfc3339(time.now(), 0, false, context.temp_allocator) or_else "??"
	content := fmt.tprintf("server_date = %s\nreal_date = %s", server_date, real_date)
	http.respond_html(res, content)
}

// Prints some json.
json_output :: proc(req: ^http.Request, res: ^http.Response) {
	// An example structure use for serialization.
	Person :: struct {
		name:       string `json:"omg_name"`,
		age:        int,
		fav_colour: string `json:"favorite_color"`,
	}

	Family :: struct {
		last_name: string,
		people:    []Person,
	}

	fam := Family {
		last_name = "Kellock",
		people    = {
			Person{"Steve", 51, "gray"},
			Person{"Myka", 51, "blue"},
			Person{"Liam", 14, "purple"},
			Person{"Matthew", 11, "teal"},
		},
	}
	http.respond_json(res, fam, .OK, {pretty = true, use_spaces = true, spaces = 2})
}

// Prints the number of bytes received via a POST.
count :: proc(req: ^http.Request, res: ^http.Response) {
	line, ok := req.line.?
	http.body(req, -1, res, proc(res: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)res

		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}

		http.respond_plain(res, fmt.tprintf("%d", len(body)))
	})
}

// Echos what was sent in the POST request body.
echo :: proc(req: ^http.Request, res: ^http.Response) {
	line, ok := req.line.?
	http.body(req, -1, res, proc(res: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)res

		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}

		http.respond_plain(res, body)
	})
}

// Parses the POST body as form encoded and prints that.
form :: proc(req: ^http.Request, res: ^http.Response) {
	line, ok := req.line.?
	http.body(req, -1, res, proc(res: rawptr, body: http.Body, err: http.Body_Error) {
		res := cast(^http.Response)res

		if err != nil {
			http.respond(res, http.body_error_status(err))
			return
		}

		sb := strings.builder_make(context.temp_allocator)
		ma, ok := http.body_url_encoded(body)
		for k, v in ma {
			fmt.sbprintf(&sb, "%s = %v\n", k, v)
		}

		http.respond_plain(res, strings.to_string(sb))
	})
}
