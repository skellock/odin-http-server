package server

import http "./odin-http"
import "core:fmt"
import "core:mem"
import "core:net"

ip_handler :: proc(req: ^http.Request, res: ^http.Response) {
	remote_ip := net.address_to_string(req.client.address, context.temp_allocator)
	http.respond_html(res, remote_ip)
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

main :: proc() {
	// the server
	server: http.Server
	http.server_shutdown_on_interrupt(&server)

	port := 8080
	endpoint := net.Endpoint{net.IP4_Any, port}

	// the router
	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)

	// configure the routes
	http.route_get(&router, "/ip", http.handler(ip_handler))
	http.route_get(&router, "/up", http.handler(up_handler))
	http.route_get(&router, "/mem", http.handler(mem_handler))

	// listen
	fmt.printf("Listening on :%d\n", port)
	root_handler := http.router_handler(&router)
	http.listen_and_serve(&server, root_handler, endpoint)
}
