// Copyright (C) 2026 Wenyi Chen

#include "save_anchor_service.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <vector>

namespace {
constexpr std::size_t kHeaderSize = 72;
constexpr std::int32_t kMaximumPayloadSize =
    100 * 1024 * 1024; // 100 MiB prototype limit.

constexpr std::uint8_t kSaveFailed = 0;
constexpr std::uint8_t kSaveSucceeded = 1;
}

save_anchor_service::save_anchor_service(
    io_context& IO,
    short port,
    connection_pool& pool_reference
) : pool(&pool_reference),
    io(&IO),
    acceptor(
        IO,
        tcp::endpoint(tcp::v4(), port)
    ) {

    std::cout
        << "Save anchor service running on port:"
        << port
        << std::endl;

    start();
}

save_anchor_service::~save_anchor_service() {
    io = nullptr;
    pool = nullptr;
}

void save_anchor_service::start() {
    auto socket = std::make_shared<tcp::socket>(*io);

    acceptor.async_accept(
        *socket,
        [this, socket](boost::system::error_code ec) {
            if (!ec) {
                std::cout
                    << "A new client has connected to save anchor service.\n";

                boost::asio::post(
                    *io,
                    [this, socket]() {
                        after_connecting(socket);
                    }
                );
            } else {
                std::cout
                    << "Error accepting new client: "
                    << ec.message()
                    << std::endl;
            }

            // Continue accepting other clients.
            start();
        }
    );
}

void save_anchor_service::after_connecting(
    std::shared_ptr<tcp::socket> socket
) {
    auto header_buffer =
        std::make_shared<std::array<char, kHeaderSize>>();

    boost::asio::async_read(
        *socket,
        boost::asio::buffer(*header_buffer),
        [this, socket, header_buffer](
            boost::system::error_code ec,
            std::size_t length
        ) {
            if (ec) {
                if (ec == boost::asio::error::eof) {
                    std::cout << "Client disconnected." << std::endl;
                } else {
                    std::cout
                        << "Error reading save header: "
                        << ec.message()
                        << std::endl;
                }

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            if (length != kHeaderSize) {
                std::cout
                    << "Wrong header size received when saving anchor."
                    << std::endl;

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            uuid anchor_id;
            std::int32_t model_id = 0;
            std::int32_t binary_data_size = 0;
            double lat = 0;
            double lon = 0;
            double alt = 0;
            double yaw = 0;
            double pitch = 0;
            double roll = 0;

            const char* data = header_buffer->data();

            std::memcpy(
                &binary_data_size,
                data,
                sizeof(binary_data_size)
            );
            std::memcpy(
                &anchor_id,
                data + sizeof(binary_data_size),
                sizeof(anchor_id)
            );
            std::memcpy(
                &model_id,
                data + sizeof(binary_data_size) + sizeof(anchor_id),
                sizeof(model_id)
            );

            const std::size_t coordinate_offset =
                sizeof(binary_data_size) +
                sizeof(anchor_id) +
                sizeof(model_id);

            std::memcpy(
                &lat,
                data + coordinate_offset,
                sizeof(lat)
            );
            std::memcpy(
                &lon,
                data + coordinate_offset + sizeof(double),
                sizeof(lon)
            );
            std::memcpy(
                &alt,
                data + coordinate_offset + 2 * sizeof(double),
                sizeof(alt)
            );
            std::memcpy(
                &yaw,
                data + coordinate_offset + 3 * sizeof(double),
                sizeof(yaw)
            );
            std::memcpy(
                &pitch,
                data + coordinate_offset + 4 * sizeof(double),
                sizeof(pitch)
            );
            std::memcpy(
                &roll,
                data + coordinate_offset + 5 * sizeof(double),
                sizeof(roll)
            );

            if (
                binary_data_size <= 0 ||
                binary_data_size > kMaximumPayloadSize
            ) {
                std::cout
                    << "Invalid visual payload size: "
                    << binary_data_size
                    << std::endl;

                auto acknowledgement =
                    std::make_shared<std::array<std::uint8_t, 1>>();
                (*acknowledgement)[0] = kSaveFailed;

                boost::asio::async_write(
                    *socket,
                    boost::asio::buffer(*acknowledgement),
                    [socket, acknowledgement](
                        boost::system::error_code,
                        std::size_t
                    ) {
                        boost::system::error_code ignored;
                        socket->close(ignored);
                    }
                );
                return;
            }

            auto binary_data_buffer =
                std::make_shared<std::vector<char>>(
                    static_cast<std::size_t>(binary_data_size)
                );

            boost::asio::async_read(
                *socket,
                boost::asio::buffer(*binary_data_buffer),
                [
                    this,
                    socket,
                    anchor_id,
                    model_id,
                    binary_data_size,
                    lat,
                    lon,
                    alt,
                    yaw,
                    pitch,
                    roll,
                    binary_data_buffer
                ](
                    boost::system::error_code ec,
                    std::size_t length
                ) mutable {
                    if (ec) {
                        if (ec == boost::asio::error::eof) {
                            std::cout
                                << "Client disconnected during payload read."
                                << std::endl;
                        } else {
                            std::cout
                                << "Error reading visual payload: "
                                << ec.message()
                                << std::endl;
                        }

                        boost::system::error_code ignored;
                        socket->close(ignored);
                        return;
                    }

                    if (
                        length !=
                        static_cast<std::size_t>(binary_data_size)
                    ) {
                        std::cout
                            << "Wrong visual payload size received."
                            << std::endl;

                        boost::system::error_code ignored;
                        socket->close(ignored);
                        return;
                    }

                    std::vector<unsigned char> binary_data(
                        binary_data_buffer->begin(),
                        binary_data_buffer->end()
                    );

                    connector database(*pool);
                    pqxx::result result = database.store_anchor(
                        anchor_id,
                        model_id,
                        lon,
                        lat,
                        alt,
                        yaw,
                        pitch,
                        roll,
                        binary_data
                    );

                    const bool saved = !result.empty();

                    if (saved) {
                        std::cout
                            << "Anchor saved to database!"
                            << std::endl;
                    } else {
                        std::cout
                            << "Error saving anchor to database."
                            << std::endl;
                    }

                    // Protocol response:
                    //   1 = committed successfully
                    //   0 = database insertion failed
                    auto acknowledgement =
                        std::make_shared<
                            std::array<std::uint8_t, 1>
                        >();

                    (*acknowledgement)[0] =
                        saved ? kSaveSucceeded : kSaveFailed;

                    boost::asio::async_write(
                        *socket,
                        boost::asio::buffer(*acknowledgement),
                        [this, socket, acknowledgement](
                            boost::system::error_code ec,
                            std::size_t length
                        ) {
                            if (ec || length != 1) {
                                std::cout
                                    << "Failed sending save acknowledgement: "
                                    << (
                                        ec
                                            ? ec.message()
                                            : "wrong acknowledgement size"
                                    )
                                    << std::endl;

                                boost::system::error_code ignored;
                                socket->close(ignored);
                                return;
                            }

                            // Keep this TCP connection available for the next
                            // anchor submitted by the same client.
                            after_connecting(socket);
                        }
                    );
                }
            );
        }
    );
}
