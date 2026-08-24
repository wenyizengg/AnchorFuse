// Copyright (C) 2026 Wenyi Chen

#ifndef CONNECTOR_H
#define CONNECTOR_H

#include <pqxx/pqxx>
#include <iostream>
#include <string>
#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <boost/uuid/string_generator.hpp>
#include "connection_pool.h"
using namespace std;

typedef pqxx::connection connection;
typedef boost::uuids::uuid uuid;

class connector{

    private:
    connection* conn;
    connection_pool* pool;


    public:
    connector(connection_pool& pool);
    ~connector();

    pqxx::result submit_query(string& query);
    pqxx::result find_nearby_anchors(double& lon, double&lat, int range);
    pqxx::result store_anchor(uuid& id, int32_t& model_id, double& lon, double& lat, double& alt, double& yaw, double& pitch, double& roll, vector<unsigned char>& remained_data); 
 
   
   
    

};

#endif