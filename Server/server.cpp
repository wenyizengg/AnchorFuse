// Copyright (C) 2026 Wenyi Chen

#include "server.h"

server::server(boost::asio::io_context& IO)
    : db_connection_str(
          "host=localhost port=5432 dbname=project"
      ),
      pool(db_connection_str, 15),
      gps_service(IO, 12345, pool),
      save_service(IO, 12347, pool),
      io(&IO),
      work_guard(boost::asio::make_work_guard(IO)) {

    unsigned int thread_count =
        std::thread::hardware_concurrency();

    // The standard permits hardware_concurrency() to return zero.
    if (thread_count == 0) {
        thread_count = 1;
    }

    thread_pool.reserve(thread_count);

    for (unsigned int i = 0; i < thread_count; ++i) {
        thread_pool.emplace_back([this]() {
            io->run();
        });
    }

    for (auto& thread : thread_pool) {
        if (thread.joinable()) {
            thread.join();
        }
    }
}

server::~server() {
    io = nullptr;
}
