package server

import http "./odin-http"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:strings"
import "core:time"

server: http.Server
router: http.Router

Person :: struct {
	name:       string `json:"omg_name"`,
	age:        int,
	fav_colour: string `json:"favorite_color"`,
}

ip_handler :: proc(req: ^http.Request, res: ^http.Response) {
	remote_ip := net.address_to_string(req.client.address, context.temp_allocator)
	http.respond_plain(res, remote_ip)
}

up_handler :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_with_status(res, .OK)
}

mem_handler :: proc(req: ^http.Request, res: ^http.Response) {
	temp_arena := (^mem.Arena)(context.temp_allocator.data)
	content := fmt.tprintf(
		"temp allocator peak bytes used = %f mb",
		f64(temp_arena.peak_used) / 1024.0 / 1024.0,
	)
	http.respond_html(res, content)
}

now_handler :: proc(req: ^http.Request, res: ^http.Response) {
	server_date := string(server.date.buf_backing[:])
	real_date := time.time_to_rfc3339(time.now(), 0, false, context.temp_allocator) or_else "??"
	content := fmt.tprintf("server_date = %s\nreal_date = %s", server_date, real_date)
	http.respond_html(res, content)
}

json_handler :: proc(req: ^http.Request, res: ^http.Response) {
	steve := [?]Person {
		Person{"Steve", 51, "gray"},
		Person{"Myka", 51, "blue"},
		Person{"Liam", 14, "purple"},
		Person{"Matthew", 11, "teal"},
	}
	http.respond_json(res, steve)
}

count_handler :: proc(req: ^http.Request, res: ^http.Response) {
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

echo_handler :: proc(req: ^http.Request, res: ^http.Response) {
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

form_handler :: proc(req: ^http.Request, res: ^http.Response) {
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

main :: proc() {
	http.server_shutdown_on_interrupt(&server)

	port := 8080
	endpoint := net.Endpoint{net.IP4_Any, port}

	// the router
	http.router_init(&router)
	defer http.router_destroy(&router)

	// configure the routes
	http.route_get(&router, "/ip", http.handler(ip_handler))
	http.route_get(&router, "/up", http.handler(up_handler))
	http.route_get(&router, "/mem", http.handler(mem_handler))
	http.route_get(&router, "/now", http.handler(now_handler))
	http.route_get(&router, "/json", http.handler(json_handler))
	http.route_post(&router, "/count", http.handler(count_handler))
	http.route_post(&router, "/echo", http.handler(echo_handler))
	http.route_post(&router, "/form", http.handler(form_handler))

	// listen
	fmt.printf("Listening on :%d\n", port)
	root_handler := http.router_handler(&router)
	http.listen_and_serve(&server, root_handler, endpoint)
}
