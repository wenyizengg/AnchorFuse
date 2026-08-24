// Copyright (C) 2026 Wenyi Chen

#include "connection_pool.h"

connection_pool::connection_pool(string &str, int number){

    this->pool.reserve(number);

    for (int i=0; i<number; i++){
        connection *temp = new connection(str);
        pool.push_back(temp);
    
    }
}

connection_pool::~connection_pool(){
    for (int i=0; i<pool.size(); i++){
        delete pool[i];
        pool[i] = nullptr;
    }
}

connection* connection_pool::get_connection(){

    unique_lock<mutex>lock (mtx); 

    condition.wait(lock, [this]{ // if pool is empty, wait till it is not.
        return !this->pool.empty(); 
    });
    
    connection* ptr = pool.back();
    pool.pop_back();

    return ptr;

}

void connection_pool::return_connction(connection *conn){

    unique_lock<mutex>lock (mtx);

    if (conn == nullptr){
        cout<<"Error occurs when returning connection to the pool. "<<endl;
        return;
    }

    pool.push_back(conn); // I will only set the conn pointer to nullptr outside. Will not use delete.

    condition.notify_one(); // notify a waiting thread (if there is any) that a connection is available.
}