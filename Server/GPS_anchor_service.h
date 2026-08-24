// Copyright (C) 2026 Wenyi Chen

#ifndef GPS_ANCHOR_SERVICE_H
#define GPS_ANCHOR_SERVICE_H

#include <boost/asio.hpp>
#include <cstdint>
#include <memory>
#include <vector>
#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <boost/uuid/string_generator.hpp>
#include "connection_pool.h"
#include "connector.h"

using namespace boost::asio;
typedef boost::asio::ip::tcp tcp;

class GPS_anchor_service {
private:
    io_context* io;
    tcp::acceptor acceptor;
    connection_pool* pool;

    void start();
    void after_connecting(std::shared_ptr<tcp::socket> socket);

    std::vector<std::uint8_t> create_buffer(
        const pqxx::result& result
    );

    void send_data(
        std::shared_ptr<std::vector<std::uint8_t>> buffer,
        std::shared_ptr<tcp::socket> socket
    );

public:
    GPS_anchor_service(
        io_context& IO,
        short port,
        connection_pool& pool
    );

    ~GPS_anchor_service();
};

#endif
