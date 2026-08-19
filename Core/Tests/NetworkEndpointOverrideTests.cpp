#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <string_view>

#include "FakeNetworkAdapter.hpp"
#include "phoneme/network/ConnectionRegistry.hpp"

namespace {

void require(bool condition, std::string_view message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

} // namespace

int main() {
    using phoneme::network::ConnectionMode;
    using phoneme::network::ConnectionRegistry;
    using phoneme::network::DatagramPacket;
    using phoneme::network::Endpoint;

    auto adapter = std::make_shared<phoneme::tests::FakeNetworkAdapter>();
    ConnectionRegistry registry(adapter);

    auto second_adapter =
        std::make_shared<phoneme::tests::FakeNetworkAdapter>();
    ConnectionRegistry second_game_registry(second_adapter);

    require(registry.set_endpoint_override(Endpoint {
                .host = "override.game.test",
                .port = 19'876,
            }).has_value(),
            "configure endpoint override");

    auto socket = registry.open("socket://original.game.test:1234",
                                ConnectionMode::read_write, true);
    require(socket.has_value(), "open outgoing TCP socket");
    auto socket_remote = registry.remote_endpoint(socket->token);
    require(socket_remote.has_value() &&
                socket_remote->host == "override.game.test" &&
                socket_remote->port == 19'876,
            "outgoing TCP uses overridden host and port");

    auto second_game_socket = second_game_registry.open(
        "socket://second.game.test:7777",
        ConnectionMode::read_write,
        true);
    require(second_game_socket.has_value(),
            "open TCP socket for a second game");
    auto second_game_remote = second_game_registry.remote_endpoint(
        second_game_socket->token);
    require(second_game_remote.has_value() &&
                second_game_remote->host == "second.game.test" &&
                second_game_remote->port == 7777,
            "one game's endpoint override does not affect another game");

    auto datagram = registry.open("datagram://:0",
                                  ConnectionMode::read_write, true);
    require(datagram.has_value(), "open locally bound UDP socket");
    require(registry.send_datagram(
                datagram->token,
                DatagramPacket {
                    .peer = Endpoint {
                        .host = "packet.original.test",
                        .port = 3456,
                    },
                    .bytes = {0x01, 0x02, 0x03},
                }).has_value(),
            "send outgoing UDP packet");
    auto packet = adapter->last_datagram();
    require(packet.has_value() &&
                packet->peer.host == "override.game.test" &&
                packet->peer.port == 19'876,
            "outgoing UDP uses overridden host and port");

    auto server = registry.open("serversocket://:2345",
                                ConnectionMode::read_write, true);
    require(server.has_value(), "open server socket");
    auto server_local = registry.local_endpoint(server->token);
    require(server_local.has_value() && server_local->port == 2345,
            "server socket bind is not rewritten");

    auto http = registry.open("http://web.original.test:8080/path",
                              ConnectionMode::read, true);
    require(http.has_value(), "open HTTP connection");
    auto http_url = registry.url(http->token);
    require(http_url.has_value() &&
                http_url->host == "web.original.test" &&
                http_url->effective_port() == 8080,
            "HTTP destination is not rewritten");

    require(!registry.set_endpoint_override(Endpoint {
                 .host = "bad host",
                 .port = 1000,
             }).has_value(),
            "reject malformed host");
    require(!registry.set_endpoint_override(Endpoint {
                 .host = "valid.test",
                 .port = 0,
             }).has_value(),
            "reject port zero");

    require(registry.set_endpoint_override(std::nullopt).has_value(),
            "clear endpoint override");
    auto original = registry.open("socket://original.game.test:4321",
                                  ConnectionMode::read_write, true);
    require(original.has_value(), "open socket after clearing override");
    auto original_remote = registry.remote_endpoint(original->token);
    require(original_remote.has_value() &&
                original_remote->host == "original.game.test" &&
                original_remote->port == 4321,
            "cleared override restores game-provided endpoint");

    registry.close_all();
    second_game_registry.close_all();
    require(adapter->open_handle_count() == 0U,
            "all native handles are released");
    require(second_adapter->open_handle_count() == 0U,
            "second game's native handles are released");

    std::cout << "PASS: per-game TCP/UDP endpoint override behavior\n";
    return 0;
}
