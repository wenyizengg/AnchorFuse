// Copyright (C) 2026 Wenyi Chen

#include "GPS_anchor_service.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
constexpr std::size_t kLocationRequestSize =
    3 * sizeof(double);

std::vector<std::uint8_t> make_zero_anchor_response() {
    const std::uint32_t anchor_count = 0;

    const auto* begin =
        reinterpret_cast<const std::uint8_t*>(&anchor_count);

    return std::vector<std::uint8_t>(
        begin,
        begin + sizeof(anchor_count)
    );
}
}

GPS_anchor_service::GPS_anchor_service(
    io_context& IO,
    short port,
    connection_pool& pool_reference
) : io(&IO),
    acceptor(
        IO,
        tcp::endpoint(tcp::v4(), port)
    ),
    pool(&pool_reference) {

    std::cout
        << "GPS anchor service running on port:"
        << port
        << std::endl;

    start();
}

GPS_anchor_service::~GPS_anchor_service() {
    io = nullptr;
    pool = nullptr;
}

void GPS_anchor_service::after_connecting(
    std::shared_ptr<tcp::socket> socket
) {
    auto request_buffer =
        std::make_shared<std::array<char, kLocationRequestSize>>();

    boost::asio::async_read(
        *socket,
        boost::asio::buffer(*request_buffer),
        [this, socket, request_buffer](
            boost::system::error_code ec,
            std::size_t length
        ) {
            if (ec) {
                if (ec == boost::asio::error::eof) {
                    std::cout << "Client disconnected." << std::endl;
                } else {
                    std::cout
                        << "Error reading device location: "
                        << ec.message()
                        << std::endl;
                }

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            if (length != kLocationRequestSize) {
                std::cout
                    << "Wrong location request size. Expected "
                    << kLocationRequestSize
                    << " bytes, received "
                    << length
                    << "."
                    << std::endl;

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            double lon = 0;
            double lat = 0;
            double alt = 0;

            const char* data = request_buffer->data();

            std::memcpy(
                &lon,
                data,
                sizeof(lon)
            );
            std::memcpy(
                &lat,
                data + sizeof(double),
                sizeof(lat)
            );
            std::memcpy(
                &alt,
                data + 2 * sizeof(double),
                sizeof(alt)
            );

            std::vector<std::uint8_t> response;

            try {
                connector database_connector(*pool);

                pqxx::result result =
                    database_connector.find_nearby_anchors(
                        lon,
                        lat,
                        100
                    );

                response = create_buffer(result);
            } catch (const std::exception& error) {
                std::cerr
                    << "Error finding nearby anchors: "
                    << error.what()
                    << std::endl;

                // The client is waiting for a four-byte anchor count.
                // Returning zero keeps the request-response stream aligned
                // and prevents pollInFlight from becoming permanently stuck.
                response = make_zero_anchor_response();
            }

            if (response.empty()) {
                std::cerr
                    << "GPS response was unexpectedly empty; "
                    << "returning zero anchors."
                    << std::endl;

                response = make_zero_anchor_response();
            }

            auto response_buffer =
                std::make_shared<std::vector<std::uint8_t>>(
                    std::move(response)
                );

            // Start the next request only after this response has been fully
            // written. This preserves one-request/one-response ordering on
            // the persistent TCP connection.
            send_data(response_buffer, socket);
        }
    );
}

void GPS_anchor_service::start() {
    auto socket = std::make_shared<tcp::socket>(*io);

    acceptor.async_accept(
        *socket,
        [this, socket](boost::system::error_code ec) {
            if (!ec) {
                std::cout
                    << "A new client has connected to GPS anchor service.\n";

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

            // Continue accepting additional clients.
            start();
        }
    );
}

std::vector<std::uint8_t> GPS_anchor_service::create_buffer(
    const pqxx::result& result
) {
    if (result.empty()) {
        std::cout << "No anchors nearby." << std::endl;
        return make_zero_anchor_response();
    }

    if (
        result.size() >
        static_cast<std::size_t>(
            std::numeric_limits<std::uint32_t>::max()
        )
    ) {
        throw std::overflow_error(
            "Nearby anchor count exceeds UInt32 capacity."
        );
    }

    const std::uint32_t anchor_count =
        static_cast<std::uint32_t>(result.size());

    std::cout
        << "Nearby anchors amount:"
        << anchor_count
        << std::endl;

    std::vector<std::uint8_t> buffer;

    const auto* count_begin =
        reinterpret_cast<const std::uint8_t*>(&anchor_count);

    buffer.insert(
        buffer.end(),
        count_begin,
        count_begin + sizeof(anchor_count)
    );

    for (const auto& row : result) {
        const std::string uuid_string = row["id"].c_str();
        boost::uuids::string_generator generator;
        const boost::uuids::uuid id = generator(uuid_string);

        const auto* id_begin =
            reinterpret_cast<const std::uint8_t*>(&id);

        buffer.insert(
            buffer.end(),
            id_begin,
            id_begin + sizeof(id)
        );

        const std::int32_t model_id =
            row["model_id"].as<std::int32_t>();

        const auto* model_begin =
            reinterpret_cast<const std::uint8_t*>(&model_id);

        buffer.insert(
            buffer.end(),
            model_begin,
            model_begin + sizeof(model_id)
        );

        const double lon = row["lon"].as<double>();
        const double lat = row["lat"].as<double>();
        const double alt = row["alt"].as<double>();
        const double yaw = row["yaw"].as<double>();
        const double pitch = row["pitch"].as<double>();
        const double roll = row["roll"].as<double>();

        const std::array<double, 6> metadata = {
            lon,
            lat,
            alt,
            yaw,
            pitch,
            roll
        };

        for (const double value : metadata) {
            const auto* value_begin =
                reinterpret_cast<const std::uint8_t*>(&value);

            buffer.insert(
                buffer.end(),
                value_begin,
                value_begin + sizeof(value)
            );
        }

        const pqxx::binarystring visual_payload(
            row["visual_localisation_data"]
        );

        if (
            visual_payload.size() == 0 ||
            visual_payload.size() >
                static_cast<std::size_t>(
                    std::numeric_limits<std::int32_t>::max()
                )
        ) {
            throw std::runtime_error(
                "Stored visual payload has an invalid size."
            );
        }

        const std::int32_t field_size =
            static_cast<std::int32_t>(visual_payload.size());

        std::cout
            << "Field size:"
            << field_size
            << std::endl;

        const auto* field_size_begin =
            reinterpret_cast<const std::uint8_t*>(&field_size);

        buffer.insert(
            buffer.end(),
            field_size_begin,
            field_size_begin + sizeof(field_size)
        );

        buffer.insert(
            buffer.end(),
            visual_payload.data(),
            visual_payload.data() + visual_payload.size()
        );
    }

    std::cout
        << "Buffer size:"
        << buffer.size()
        << std::endl;

    return buffer;
}

void GPS_anchor_service::send_data(
    std::shared_ptr<std::vector<std::uint8_t>> buffer,
    std::shared_ptr<tcp::socket> socket
) {
    boost::asio::async_write(
        *socket,
        boost::asio::buffer(*buffer),
        [this, socket, buffer](
            boost::system::error_code ec,
            std::size_t length
        ) {
            if (ec) {
                std::cout
                    << "Error sending nearby anchors: "
                    << ec.message()
                    << std::endl;

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            if (length != buffer->size()) {
                std::cout
                    << "Incomplete GPS response write. Expected "
                    << buffer->size()
                    << " bytes, wrote "
                    << length
                    << "."
                    << std::endl;

                boost::system::error_code ignored;
                socket->close(ignored);
                return;
            }

            std::cout
                << "Nearby anchors sent successfully, data size:"
                << length
                << std::endl;

            after_connecting(socket);
        }
    );
}
