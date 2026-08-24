// Copyright (C) 2026 Wenyi Chen

#include <iostream>
#include <pqxx/pqxx>
#include <boost/asio.hpp>
#include "server.h"


// ######## note that in pqxx, connection objects cannot be duplicated. 
// Hence can only passed by pointers or references.

using namespace std;
int main() {


    //std::cout << cv::getBuildInformation() << std::endl;

    boost::asio::io_context io;
    server server_ = server(io);
  
    
    return 0;
}

