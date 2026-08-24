// Copyright (C) 2026 Wenyi Chen

#include "connector.h"



connector::connector(connection_pool &pool){
    this->pool = &pool;
    this->conn = this->pool->get_connection();
}

connector::~connector(){

    pool->return_connction(conn);
    conn = nullptr;
    pool = nullptr;
    
}





pqxx::result connector::find_nearby_anchors(double& lon, double& lat, int range) {
   
    std::string query =
        "SELECT id, model_id, "
        "ST_X(location) AS lon, "
        "ST_Y(location) AS lat, "
        "ST_Z(location) AS alt, "
        "yaw, pitch, roll, visual_localisation_data, "
        "ST_Distance("
            "location::geography, "
            "ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography"
        ") AS distance "
        "FROM anchor "
        "WHERE ST_DWithin("
            "location::geography, "
            "ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, "
            "$3"
        ");";

    try {
        pqxx::work txn(*conn);

       
        pqxx::result res = txn.exec_params(
            query,
            lon,   
            lat,   
            range 
        );

        txn.commit();
        return res;

    } catch (const std::exception& e) {
        std::cerr << "Error finding nearby anchors: " << e.what() << std::endl;
        throw; // re-throw the error outside
    }
}


pqxx::result connector::store_anchor(
    uuid& id, 
    int32_t& model_id, 
    double& lon, 
    double& lat, 
    double& alt, 
    double& yaw, 
    double& pitch, 
    double& roll, 
    vector<unsigned char>& remained_data
) {
    // Convert UUID to string
    std::string id_str = boost::uuids::to_string(id);

    pqxx::binarystring remained_bytes(reinterpret_cast<const char*>(remained_data.data()), remained_data.size());


    // Create a query
    std::string query = 
        "INSERT INTO public.anchor (id, model_id, location, yaw, pitch, roll, visual_localisation_data) "
        "VALUES ($1::uuid, $2, ST_SetSRID(ST_MakePoint($3, $4, $5), 4326), $6, $7, $8, $9) "
        "RETURNING id";

    try {
        
        pqxx::work txn(*conn); 

        // Execute the query with parameters
        pqxx::result res = txn.exec_params(
            query,
            id_str,   
            model_id, 
            lon,      
            lat,    
            alt,     
            yaw,  
            pitch,    
            roll,
            remained_bytes      
        );

        
        txn.commit();
        return res;

    } catch (const exception& e) {
        std::cerr << "Error inserting anchor: " << e.what() << std::endl;
        return pqxx::result();
       // throw; // Re-throw the exception
    } 

}

 

    