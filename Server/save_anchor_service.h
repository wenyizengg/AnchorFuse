// Copyright (C) 2026 Wenyi Chen

#ifndef SAVE_ANCHOR_SERVICE_H
#define SAVE_ANCHOR_SERVICE_H
#include "connection_pool.h"
#include "connector.h"
#include <boost/asio.hpp>
#include <memory>
#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <boost/uuid/string_generator.hpp>



using namespace boost::asio;
typedef boost::asio::ip::tcp tcp;
typedef boost::uuids::uuid uuid;

class save_anchor_service{

    private:
    connection_pool* pool;
    io_context* io;
    tcp::acceptor acceptor;

    void start();
    void after_connecting(std::shared_ptr<tcp::socket> socket);


    public:
    save_anchor_service(io_context& IO, short port, connection_pool& pool);
    ~save_anchor_service();
};




#endif