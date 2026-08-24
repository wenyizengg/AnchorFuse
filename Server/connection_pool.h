// Copyright (C) 2026 Wenyi Chen

#ifndef CONNECTION_POOL_H
#define CONNECTION_POOL_H

#include <pqxx/pqxx>
#include <iostream>
#include <vector>
#include <string>
#include <mutex>
#include <condition_variable>

using namespace std;
typedef pqxx::connection connection;

class connection_pool{

    private:
    
    vector<connection*> pool;
    mutex mtx;
    condition_variable condition; 
    
    
    public:

    connection_pool(string &str, int number);
    ~connection_pool();

    connection* get_connection();
    void return_connction (connection *conn);




};

#endif // CONNECTION_POOL_H