// Copyright (C) 2026 Wenyi Chen

#ifndef SERVER_H
#define SERVER_H

#include <string>
#include <thread>
#include <vector>

#include <boost/asio.hpp>

#include "GPS_anchor_service.h"
#include "save_anchor_service.h"

class server {
private:
    // Members are constructed in declaration order.
    // The database configuration and pool must therefore be declared before
    // the services that receive references to the pool.
    std::string db_connection_str;
    connection_pool pool;

    GPS_anchor_service gps_service;
    save_anchor_service save_service;

    boost::asio::io_context* io;
    boost::asio::executor_work_guard<
        boost::asio::io_context::executor_type
    > work_guard;

    std::vector<std::thread> thread_pool;

public:
    explicit server(boost::asio::io_context& io);
    ~server();
};

#endif
